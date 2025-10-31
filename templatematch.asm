# LAST NAME Hou
# First name Jocelyn
# Student number 261235618

# Q1: Do the base addresses of image and error buffers fall into the same block of the direct mapped cache?
# Yes, they fall into the same block in direct mapped cache.
# block contains 4 words = 16 bytes = 2^4 bytes, need 4 bits to specify correct byte
# cache is 128 bytes = 2^7 bytes, need 7 bits to specify index
# we know image and error buffer regions are placed at the beginning of the static data 0x10010000
# so image buffer is at 0x10010000, and error buffer is at 0x10050000
# image address: (0001 0000 0000 0001 0000 0)(000 0000) (0000)
# error address: (0001 0000 0000 0101 0000 0)(000 0000) (0000)
# both have the same index and byte offset so they will map to the same cache block
# Q2: For the templateMatchFast and a direct mapped cache, does it matter if the template buffer base address falls into the same block as the image or error buffer base address?
# Yes, it does matter, because templateMatchFast repeatedly access the template, image, and error buffer base addresses
# if the template buffer shares a cache block with either the image or error buffer, conflict misses will occur.
# This means frequence cache misses and block replacements, which will hurt performance.

# These are questions I answered before doing the measurements.
# In the instructions it's stated "Altering the memory layout in your data segment by adding .space directives as necessary to make your fast implementation work well with the direct mapped cache"
# so I will include padding that will halp direct mapped cache on line 24 and 26
.data
displayBuffer:  .space 0x40000 # 512x256 bitmap display (0x200 by 0x80 times 4 bytes)
		.space 128         # note: pad 128 bytes = full cache size. THIS IS SOMETHING I ADDED
errorBuffer:    .space 0x40000 # space to store match function
		.space 128         # note: pad 128 bytes = full cache size. THIS IS SOMETHING I ADDED
templateBuffer: .space 0x100   # space for 8x8 template
imageFileName:    .asciiz "pxlcon512x256cropgs.raw" 
templateFileName: .asciiz "template8x8gs.raw"
.align 2 # ensure following labels are word aligned
# struct bufferInfo { int *buffer, int width, int height, char* filename }
imageBufferInfo:    .word displayBuffer  512 16  imageFileName
errorBufferInfo:    .word errorBuffer    512 16  0
templateBufferInfo: .word templateBuffer 8   8    templateFileName

.text
main:	la $a0, imageBufferInfo
	jal loadImage
	la $a0, templateBufferInfo
	jal loadImage
	la $a0, imageBufferInfo
	la $a1, templateBufferInfo
	la $a2, errorBufferInfo
	jal matchTemplateFast        # MATCHING DONE HERE
	la $a0, errorBufferInfo
	jal findBest
	la $a0, imageBufferInfo
	move $a1, $v0
	jal highlight
	la $a0, errorBufferInfo	
	jal processError
	li $v0, 10		# exit
	syscall
	

##########################################################
# matchTemplate( bufferInfo imageBufferInfo, bufferInfo templateBufferInfo, bufferInfo errorBufferInfo )
# NOTE: struct bufferInfo { int *buffer, int width, int height, char* filename }
matchTemplate:	
	# TODO: write this function!
	
	addi $sp, $sp, -36
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $s2, 8($sp)
	sw $s3, 12($sp)
	sw $s4, 16($sp)
	sw $s5, 20($sp)
	sw $s6, 24($sp)
	sw $s7, 28($sp)
	sw $ra, 32($sp)
	
	lw $s0, 0($a0) # display Buffer Pointer
	lw $s1, 4($a0) # image width
	lw $s2, 8($a0) # image height
	
	lw $s3, 0($a1) # template Buffer Pointer
	
	lw $s4, 0($a2) # error Buffer Pointer
	
	# note: assigning $t9 to hold all the constants for comparisons
	
	li $t0, 0 # y = 0
	
yLoop:
	# condition is y <= height - 8
	# 8 <= height - y
	sub $t1, $s2, $t0 # t1 = image height - y
	li $t9, 8
	bgt $t9, $t1, matchTemplateFinish # if 8 > image height - y, loop finish
	
	li $t2, 0 # x = 0
	
xLoop:
	# condition is x <= width - 8
	# 8 <= width - x
	sub $t3, $s1, $t2 # t3 = image width - x
	li $t9, 8
	bgt $t9, $t3, endx # if 8 > image width - x, go to endx
	
	li $s5, 0 # SAD = 0
	
	li $t4, 0 # j = 0
jLoop: 
	# condition is j < 8
	bge $t4, 8, endj # if j  >= 8, go to endj
	
	li $t5, 0 # i = 0
	
iLoop:
	# condition is i < 8
	bge $t5, 8, endi # if i  >= 8, go to endi
	
	# image index = ((y + j) * imageWidth + (x + i)) * 4
	add $t6, $t0, $t4 # t6 = y + j
	mul $t6, $t6, $s1 # * image width
	add $t6, $t6, $t2 # + x
	add $t6, $t6, $t5 # + i
	sll $t6, $t6, 2 # convert to byte
	add $t7, $s0, $t6
	lbu $s6, 0($t7) # imagePixel
	
	# template index = (j * templateWidth + i) * 4
	mul $t8, $t4, 8 # j * 8
	add $t8, $t8, $t5 # + i
	sll $t8, $t8, 2 # * 4
	add $t9, $s3, $t8
	lbu $s7, 0($t9) # templatePixel
	
	sub $t1, $s6, $s7 # I[x+i][y+j] - T[i][j]
	bgez $t1, skipAbs # if $t1 > 0, go to skipAbs
	sub $t1, $0, $t1 # $t1 = 0 - $t1
skipAbs:
	add $s5, $s5, $t1 # SAD = SAD + $t1
	
	addiu $t5, $t5, 1 # increase i counter by 1
	j iLoop # go back to beginning of iLoop
	
endi:
	# no longer meets condition to enter iLoop
	addi $t4, $t4, 1 # increase j counter by 1
	j jLoop # go back to beginning of jLoop

endj:
	# no longer meets condition to enter jLoop, so finished calculating SAD[x,y]
	# finding where to place SAD in errorBuffer
	# error index = (y * image width + x) * 4
	mul $t3, $t0, $s1 # y * image width
	add $t3, $t3, $t2 # + x
	sll $t3, $t3, 2 # * 4
	add $t3, $t3, $s4
	sw $s5, 0($t3) # store SAD in the correct place of errorBuffer
	
	addi $t2, $t2, 1 # increase x counter by 1
	j xLoop # go back to beginning of xLoop
	
endx:
	# no longer meets condition to enter xLoop
	addi $t0, $t0, 1 # increase y counter by 1
	j yLoop # go back to beginning of yLoop

matchTemplateFinish:
	# no longer meets condition to enter yLoop
	lw $s0, 0($sp) # restore registers
	lw $s1, 4($sp)
	lw $s2, 8($sp)
	lw $s3, 12($sp)
	lw $s4, 16($sp)
	lw $s5, 20($sp)
	lw $s6, 24($sp)
	lw $s7, 28($sp)
	lw $ra, 32($sp)
	addi $sp, $sp, 36
	jr $ra	
	
##########################################################
# matchTemplateFast( bufferInfo imageBufferInfo, bufferInfo templateBufferInfo, bufferInfo errorBufferInfo )
# NOTE: struct bufferInfo { int *buffer, int width, int height, char* filename }
matchTemplateFast:	
	
	# TODO: write this function!
	addi $sp, $sp, -32 # saving $sX onto the stack
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $s2, 8($sp)
	sw $s3, 12($sp)
	sw $s4, 16($sp)
	sw $s5, 20($sp)
	sw $s6, 24($sp)
	sw $s7, 28($sp)

	li $t8, 0 # j = 0
	lw $s5, 0($a1) # $s5 = template base address
	lw $s6, 8($a0) # $s6 = image height
	lw $s7, 4($a0) # $s7 = image width
	
jLoopMTF:
	# condition is j < 8
	bge $t8, 8, mtfFinish # if j  >= 8, go to mtfFinish

	mul $s1, $t8, 8 # determing the offset, j * templateWidth
	sll $s1, $s1, 2 # * 4
	add $s2, $s5, $s1 # template base address + offset

	lbu $t0, 0($s2) # offset increases by 4*i, from t0 to t7
	lbu $t1, 4($s2)
	lbu $t2, 8($s2)
	lbu $t3, 12($s2)
	lbu $t4, 16($s2)
	lbu $t5, 20($s2)
	lbu $t6, 24($s2)
	lbu $t7, 28($s2)

	li $t9, 0 # y = 0
yLoopMTF:
	# condition is y <= height - 8
	# y + 8 <= height
	addi $t9, $t9, 8 # so start at y = 8 rather than y = 0
	bgt $t9, $s6, endyMTF # if y + 8 > height, go to endyMTF
	subi $t9, $t9, 8 # subtract 8 to get orginal y value back
	# why? because I need it to calculate SAD, and I'm running out of registers

	li $s3, 0 # x = 0
xLoopMTF:
	# condition is x <= width - 8
	# x + 8 <= width
	addi $s3, $s3, 8 # so start at x = 8 rather than x = 0
	bgt $s3, $s7, endxMTF # if x + 8 > width, go to endxMTF
	subi $s3, $s3, 8 # subtract 8 to get orginal x value back
	# why? because I need it to calculate SAD, and I'm running out of registers
	
	# error index = (y * image width + x) * 4
	mul $s1, $t9, $s7 # y * image width
	add $s1, $s1, $s3 # + x
	sll $s1, $s1, 2 # * 4
	lw $s0, 0($a2) # $s0 = error base address
	add $s1, $s1, $s0 # offset + error base address
	lw $s4, 0($s1) # SAD[x,y]
	
	add $s1, $t9, $t8 # y + j
	mul $s1, $s1, $s7 # * image width
	add $s1, $s1, $s3 # + x
	sll $s1, $s1, 2 # * 4
	lw $s0, 0($a0) # $s0 = image base address
	add $s1, $s1, $s0 # offset + image base address
	
	lbu $s2, 0($s1) # $s2 = I[x+0][y+j]
	sub $s2, $s2, $t0 # I[x+0][y+j] - t0
	abs $s2, $s2 # abs(I[x+0][y+j] - t0)
	add $s4, $s4, $s2 # add to SAD
	
	lbu $s2, 4($s1) # $s2 = I[x+1][y+j], 4 for byte offset
	sub $s2, $s2, $t1 # I[x+1][y+j] - t1
	abs $s2, $s2 # abs(I[x+1][y+j] - t1)
	add $s4, $s4, $s2 # add to SAD
	
	lbu $s2, 8($s1) # $s2 = I[x+2][y+j], 8 for byte offset
	sub $s2, $s2, $t2 # I[x+2][y+j] - t2
	abs $s2, $s2 # abs(I[x+2][y+j] - t2)
	add $s4, $s4, $s2 # add to SAD
	
	lbu $s2, 12($s1) # $s2 = I[x+3][y+j], 12 for byte offset
	sub $s2, $s2, $t3 # I[x+3][y+j] - t3
	abs $s2, $s2 # abs(I[x+3][y+j] - t3)
	add $s4, $s4, $s2 # add to SAD
	
	lbu $s2, 16($s1) # $s2 = I[x+4][y+j], 16 for byte offset
	sub $s2, $s2, $t4 # I[x+4][y+j] - t4
	abs $s2, $s2 # abs(I[x+4][y+j] - t4)
	add $s4, $s4, $s2 # add to SAD
	
	lbu $s2, 20($s1) # $s2 = I[x+5][y+j], 20 for byte offset
	sub $s2, $s2, $t5 # I[x+5][y+j] - t5
	abs $s2, $s2 # abs(I[x+5][y+j] - t5)
	add $s4, $s4, $s2 # add to SAD
	
	lbu $s2, 24($s1) # $s2 = I[x+6][y+j], 24 for byte offset
	sub $s2, $s2, $t6 # I[x+6][y+j] - t6
	abs $s2, $s2 # abs(I[x+6][y+j] - t6)
	add $s4, $s4, $s2 # add to SAD

	lbu $s2, 28($s1) # $s2 = I[x+7][y+j], 28 for byte offset
	sub $s2, $s2, $t7 # I[x+7][y+j] - t7
	abs $s2, $s2 # abs(I[x+7][y+j] - t7)
	add $s4, $s4, $s2 # add to SAD
	
	mul $s1, $t9, $s7 # y * image width
	add $s1, $s1, $s3 # + x
	sll $s1, $s1, 2 # * 4
	lw $s0, 0($a2) # $s0 = error base address
	add $s1, $s1, $s0 # offset + error base address
	sw $s4, 0($s1) # store SAD in the correct place of errorBuffer

	addi $s3, $s3, 1 # increase x counter by 1
	j xLoopMTF # go back to beginning of xLoopMTF

endxMTF:
	# no longer meets condition to enter xLoopMTF
	addi $t9, $t9, 1 # increase y counter by 1
	j yLoopMTF # go back to beginning of yLoopMTF
endyMTF:
	# no longer meets condition to enter yLoopMTF
	addi $t8, $t8, 1 # increase j counter by 1
	j jLoopMTF # go back to beginning of jLoopMTF

mtfFinish:
	# no longer meets condition to enter jLoopMTF
	lw $s0, 0($sp) # restore registers
	lw $s1, 4($sp)
	lw $s2, 8($sp)
	lw $s3, 12($sp)
	lw $s4, 16($sp)
	lw $s5, 20($sp)
	lw $s6, 24($sp)
	lw $s7, 28($sp)
	addi $sp, $sp, 32
	jr $ra

###############################################################
# loadImage( bufferInfo* imageBufferInfo )
# NOTE: struct bufferInfo { int *buffer, int width, int height, char* filename }
loadImage:	lw $a3, 0($a0)  # int* buffer
		lw $a1, 4($a0)  # int width
		lw $a2, 8($a0)  # int height
		lw $a0, 12($a0) # char* filename
		mul $t0, $a1, $a2 # words to read (width x height) in a2
		sll $t0, $t0, 2	  # multiply by 4 to get bytes to read
		li $a1, 0     # flags (0: read, 1: write)
		li $a2, 0     # mode (unused)
		li $v0, 13    # open file, $a0 is null-terminated string of file name
		syscall
		move $a0, $v0     # file descriptor (negative if error) as argument for read
  		move $a1, $a3     # address of buffer to which to write
		move $a2, $t0	  # number of bytes to read
		li  $v0, 14       # system call for read from file
		syscall           # read from file
        		# $v0 contains number of characters read (0 if end-of-file, negative if error).
        		# We'll assume that we do not need to be checking for errors!
		# Note, the bitmap display doesn't update properly on load, 
		# so let's go touch each memory address to refresh it!
		move $t0, $a3	   # start address
		add $t1, $a3, $a2  # end address
loadloop:	lw $t2, ($t0)
		sw $t2, ($t0)
		addi $t0, $t0, 4
		bne $t0, $t1, loadloop
		jr $ra
		
		
#####################################################
# (offset, score) = findBest( bufferInfo errorBuffer )
# Returns the address offset and score of the best match in the error Buffer
findBest:	lw $t0, 0($a0)     # load error buffer start address	
		lw $t2, 4($a0)	   # load width
		lw $t3, 8($a0)	   # load height
		addi $t3, $t3, -7  # height less 8 template lines minus one
		mul $t1, $t2, $t3
		sll $t1, $t1, 2    # error buffer size in bytes	
		add $t1, $t0, $t1  # error buffer end address
		li $v0, 0		# address of best match	
		li $v1, 0xffffffff 	# score of best match	
		lw $a1, 4($a0)    # load width
        		addi $a1, $a1, -7 # initialize column count to 7 less than width to account for template
fbLoop:		lw $t9, 0($t0)        # score
		sltu $t8, $t9, $v1    # better than best so far?
		beq $t8, $zero, notBest
		move $v0, $t0
		move $v1, $t9
notBest:		addi $a1, $a1, -1
		bne $a1, $0, fbNotEOL # Need to skip 8 pixels at the end of each line
		lw $a1, 4($a0)        # load width
        		addi $a1, $a1, -7     # column count for next line is 7 less than width
        		addi $t0, $t0, 28     # skip pointer to end of line (7 pixels x 4 bytes)
fbNotEOL:	add $t0, $t0, 4
		bne $t0, $t1, fbLoop
		lw $t0, 0($a0)     # load error buffer start address	
		sub $v0, $v0, $t0  # return the offset rather than the address
		jr $ra
		

#####################################################
# highlight( bufferInfo imageBuffer, int offset )
# Applies green mask on all pixels in an 8x8 region
# starting at the provided addr.
highlight:	lw $t0, 0($a0)     # load image buffer start address
		add $a1, $a1, $t0  # add start address to offset
		lw $t0, 4($a0) 	# width
		sll $t0, $t0, 2	
		li $a2, 0xff00 	# highlight green
		li $t9, 8	# loop over rows
highlightLoop:	lw $t3, 0($a1)		# inner loop completely unrolled	
		and $t3, $t3, $a2
		sw $t3, 0($a1)
		lw $t3, 4($a1)
		and $t3, $t3, $a2
		sw $t3, 4($a1)
		lw $t3, 8($a1)
		and $t3, $t3, $a2
		sw $t3, 8($a1)
		lw $t3, 12($a1)
		and $t3, $t3, $a2
		sw $t3, 12($a1)
		lw $t3, 16($a1)
		and $t3, $t3, $a2
		sw $t3, 16($a1)
		lw $t3, 20($a1)
		and $t3, $t3, $a2
		sw $t3, 20($a1)
		lw $t3, 24($a1)
		and $t3, $t3, $a2
		sw $t3, 24($a1)
		lw $t3, 28($a1)
		and $t3, $t3, $a2
		sw $t3, 28($a1)
		add $a1, $a1, $t0	# increment address to next row	
		add $t9, $t9, -1		# decrement row count
		bne $t9, $zero, highlightLoop
		jr $ra

######################################################
# processError( bufferInfo error )
# Remaps scores in the entire error buffer. The best score, zero, 
# will be bright green (0xff), and errors bigger than 0x4000 will
# be black.  This is done by shifting the error by 5 bits, clamping
# anything bigger than 0xff and then subtracting this from 0xff.
processError:	lw $t0, 0($a0)     # load error buffer start address
		lw $t2, 4($a0)	   # load width
		lw $t3, 8($a0)	   # load height
		addi $t3, $t3, -7  # height less 8 template lines minus one
		mul $t1, $t2, $t3
		sll $t1, $t1, 2    # error buffer size in bytes	
		add $t1, $t0, $t1  # error buffer end address
		lw $a1, 4($a0)     # load width as column counter
        		addi $a1, $a1, -7  # initialize column count to 7 less than width to account for template
pebLoop:		lw $v0, 0($t0)        # score
		srl $v0, $v0, 5       # reduce magnitude 
		slti $t2, $v0, 0x100  # clamp?
		bne  $t2, $zero, skipClamp
		li $v0, 0xff          # clamp!
skipClamp:	li $t2, 0xff	      # invert to make a score
		sub $v0, $t2, $v0
		sll $v0, $v0, 8       # shift it up into the green
		sw $v0, 0($t0)
		addi $a1, $a1, -1        # decrement column counter	
		bne $a1, $0, pebNotEOL   # Need to skip 8 pixels at the end of each line
		lw $a1, 4($a0)        # load width to reset column counter
        		addi $a1, $a1, -7     # column count for next line is 7 less than width
        		addi $t0, $t0, 28     # skip pointer to end of line (7 pixels x 4 bytes)
pebNotEOL:	add $t0, $t0, 4
		bne $t0, $t1, pebLoop
		jr $ra
