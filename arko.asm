	.eqv	CHUNK_SIZE,	4096	# how much to read from file in one go
	.eqv	FILENAME_SIZE,	256	# max file name length
	.eqv	DICT_SIZE,	65536	# max entries in the LZW dictionary
	.eqv	LZW_BITS,	10	# how many bits to use per output code
	.eqv	PRINTI,		1
	.eqv	PRINTS,		4
	.eqv	READI,		5
	.eqv	READS,		8
	.eqv	SBRK,		9
	.eqv	EXIT,		10
	.eqv	CLOSE,		57
	.eqv	LSEEK,		62
	.eqv	READ,		63
	.eqv	WRITE,		64
	.eqv	OPEN,		1024
	
	
	.data
filename:	.space	FILENAME_SIZE
pick_file:	.asciz	"File name:\n"
pick_mode:	.asciz	"Do you want to compress (1) or decompress (2)?\n"
file_err_str:	.asciz	"There was an error opening the given file.\n"
file_op_str:	.asciz	"An error occured while operating on the given file.\n"
out_file:	.asciz	"Output file name:\n"
origin_table:	.space	256
no_input:	.asciz	"The input is empty, nothing to do.\n"
used_bits:	.asciz	"Dictionary space used:\n"
newline:	.asciz	"\n"


	.macro exit
	li	a7, EXIT
	ecall
	.end_macro
	
	.macro exit_with_str (%x)
	la	a0, %x
	li	a7, PRINTS
	ecall
	exit
	.end_macro


	.text
	.global main
main:
	la	a0, pick_file
	li	a7, PRINTS
	ecall
	la	a0, filename
	li	a1, FILENAME_SIZE
	li	a7, READS
	ecall
	call	sanitize_str
	call	read_file
	mv	s0, a0		# s0 = src buffer
	mv	s1, zero	# s1 = src used length
	mv	s2, zero	# s2 = src bit index
	mv	s3, a1		# s3 = src total size
	
	beqz	s3, input_empty
	
	li	s4, DICT_SIZE
	li	s5, 12
	mul	s5, s4, s5	# s5 = byte dict size
	mv	a0, s5
	li	a7, SBRK
	ecall
	mv	s4, a0		# s4 = dict ptr
	add	t0, a0, a1
memzero_loop:
	beq	a0, t0, memzero_end
	sw	zero, (a0)
	addi	a0, a0, 4
memzero_end:
	mv	s6, zero	# s6 = dict index
	
	# s11 = return address save / temporary
	
	li	s10, CHUNK_SIZE	# s10 = output total size
	mv	a0, s10
	li	a7, SBRK
	ecall
	mv	s7, a0		# s7 = output buffer
	mv	s8, zero	# s8 = output used length
	mv	s9, zero	# s9 = output bit index
	
	la	a0, pick_mode
	li	a7, PRINTS
	ecall
	li	a7, READI
	ecall
	addi	a0, a0, -1
	beqz	a0, comp
	call	decompress
	b	after
comp:
	call	compress
	
	la	a0, used_bits
	li	a7, PRINTS
	ecall
	
	mv	a0, s6
	li	a7, PRINTI
	ecall
	
	la	a0, newline
	li	a7, PRINTS
	ecall
after:
	
	la	a0, out_file
	li	a7, PRINTS
	ecall
	la	a0, filename
	li	a1, FILENAME_SIZE
	li	a7, READS
	ecall
	call	sanitize_str
	mv	a1, s7
	mv	a2, s8
	addi	s9, s9, 7
	srli	s9, s9, 3
	add	s8, s8, s9
	call	write_file
	
	exit
	
	
sanitize_str:	# a0 = string
	addi	t0, a0, -1
sanitize_loop:
	addi	t0, t0, 1
	lb	tp, (t0)
	xori	tp, tp, 0x0a
	beqz	tp, sanitize_end
	b	sanitize_loop
sanitize_end:
	sb	zero, (t0)
	ret
	
	
read_file:	# a0 = file name
	mv	a1, zero
	li	a7, OPEN
	ecall
	blt	a0, zero, file_err
	mv	t0, a0
	
	mv	a2, zero
	li	a7, LSEEK
	ecall
	blt	a0, zero, file_op_err
	
	li	a0, CHUNK_SIZE
	li	a7, SBRK
	ecall
	mv	tp, a0
	
	mv	a0, t0
	mv	a1, tp
	li	a2, CHUNK_SIZE
	li	t2, CHUNK_SIZE
	li	a7, READ
read_loop:
	ecall
	blt	a0, zero, file_op_err
	sub	a2, a2, a0
	add	a1, a1, a0
	blt	a0, t2, read_end
	
	li	a0, CHUNK_SIZE
	li	a7, SBRK
	ecall
	li	a2, CHUNK_SIZE
	mv	a0, t0
	li	a7, READ
	b	read_loop
	
read_end:
	li	a7, CLOSE
	ecall
	
	mv	a0, tp
	sub	a1, a1, tp
	add	t0, a0, a1
	sb	zero, (t0)
	ret
	
	
write_file:	# a0 = file name, a1 = buffer to write, a2 = buffer length
	mv	tp, a1
	
	li	a1, 1
	li	a7, OPEN
	ecall
	blt	a0, zero, file_err
	mv	t0, a0
	
	mv	a1, tp
	li	a7, WRITE
	ecall
	bne	a0, a2, file_op_err
	
	mv	a0, t0
	li	a7, CLOSE
	ecall
	
	ret
	
	
fnv_1a:		# a0 = data ptr, a1 = length
	li	a2, 0x01000193
	li	a7, 0x811c9dc5
	add	a5, a0, a1
	mv	a3, a0
fnv_1a_loop:
	lb	a6, (a3)
	xor	a7, a7, a6
	mul	a7, a7, a2
	addi	a3, a3, 1
	bne	a3, a5, fnv_1a_loop
	
	li	a6, 12
	mul	a7, a6, a7
	remu	a2, a7, s5
	add	a3, a2, s4
	ret
	
	
hash_put:	# a0 = data ptr, a1 = length
	mv	s11, ra
	call	fnv_1a
	mv	ra, s11
hash_put_loop:
	lw	a4, (a3)
	bnez	a4, hash_put_cont
	b	hash_put_end
hash_put_cont:
	addi	a2, a2, 12
	remu	a2, a2, s5
	add	a3, a2, s4
	b	hash_put_loop
hash_put_end:
	sw	a0, (a3)
	sw	a1, 4(a3)
	sw	s6, 8(a3)
	addi	s6, s6, 1
	ret
	
	
hash_get:	# a0 = data ptr, a1 = length
	mv	s11, ra
	call	fnv_1a
	mv	ra, s11
hash_get_loop:
	lw	a4, (a3)
	beqz	a4, hash_get_no_end
	lw	a5, 4(a3)
	bne	a5, a1, hash_get_next
	add	s11, a0, a1
	mv	a6, a0
hash_get_memcmp:
	lb	a7, (a4)
	lb	tp, (a6)
	sub	a7, a7, tp
	bnez	a7, hash_get_next
	addi	a6, a6, 1
	beq	a6, s11, hash_get_end
	addi	a4, a4, 1
	b	hash_get_memcmp
	
hash_get_next:
	addi	a2, a2, 12
	remu	a2, a2, s5
	add	a3, a2, s4
	b	hash_get_loop
	
hash_get_end:	# success
	mv	a2, zero
	lw	a3, 8(a3)
	ret
hash_get_no_end:
	li	a2, 1
	ret
	
	
can_read:	# a0 = bits
	add	a1, s2, a0
	srli	a1, a1, 3
	add	a1, a1, s1
	bleu	a1, s3, can_read_skip
	mv	a0, zero
can_read_skip:
	ret
	
	
str_put:	# a0 = data ptr, a1 = length
	add	a2, s4, s6
	addi	s6, s6, 8
	sw	a0, (a2)
	sw	a1, 4(a2)
	ret
	
	
str_get:	# a0 = code
	bgeu	a0, s6, str_get_fail
	slli	a1, a0, 3
	add	a1, a1, s4
	lw	a0, (a1)
	lw	a1, 4(a1)
	ret
str_get_fail:
	mv	a0, zero
	mv	a1, zero
	ret
	
	
create_entry:	# a0 = first str, a1 = first str length, a2 = second str
	lb	a2, (a2)
	sb	a2, -1(sp)
	addi	a2, a1, 1
	sub	sp, sp, a2
	add	a3, s4, s6
	addi	s6, s6, 8
	sw	sp, (a3)
	sw	a2, 4(a3)
	mv	a4, sp
	mv	a5, a2
	add	a1, a0, a1
	mv	a2, sp
create_entry_loop:
	beq	a0, a1, create_entry_end
	lb	a3, (a0)
	sb	a3, (a2)
	addi	a0, a0, 1
	addi	a2, a2, 1
	b	create_entry_loop
create_entry_end:
	mv	a0, a4
	mv	a1, a5
	ret
	
	
write_str:	# a0 = data ptr, a1 = length
	mv	a3, a0
	add	a4, s7, s8
	add	a5, a0, a1
	
	add	a2, s8, a1
	bgtu	a2, s10, write_str_resize
	b	write_str_loop
write_str_resize:
	mv	a2, a0
	li	a0, CHUNK_SIZE
	add	s10, s10, a0
	li	a6, SBRK
	ecall
	mv	a0, a2
	
write_str_loop:
	lb	a2, (a3)
	sb	a2, (a4)
	addi	a3, a3, 1
	addi	a4, a4, 1
	bne	a3, a5, write_str_loop

	add	s8, s8, a1
	ret
	
	
write_bits:	# a0 = bits, a1 = number
	add	a2, s7, s8
	
	add	a3, s9, a0
	srli	a3, a3, 3
	add	a3, a3, s8
	bgtu	a3, s10, write_bits_resize
	b	write_bits_loop
write_bits_resize:
	mv	a3, a0
	li	a0, CHUNK_SIZE
	add	s10, s10, a0
	li	a7, SBRK
	ecall
	mv	a0, a3
	
write_bits_loop:
	beqz	a0, write_bits_end
	lb	a4, (a2)
	addi	a3, a0, -8
	add	a3, a3, s9
	bltz	a3, write_bits_negative
	srl	a7, a1, a3
	or	a4, a4, a7
	sb	a4, (a2)
	addi	a2, a2, 1
	mv	s9, zero
	mv	a0, a3
	b	write_bits_loop
write_bits_negative:
	sub	a3, zero, a3
	sll	a7, a1, a3
	or	a4, a4, a7
	sb	a4, (a2)
	add	a5, a0, s9
	srli	a6, a5, 3
	add	a2, a2, a6
	andi	s9, a5, 7
write_bits_end:
	sub	s8, a2, s7
	ret


read_bits:	# a0 = bits
	mv	a1, zero
	mv	a7, a0
	add	a2, s0, s1
read_bits_loop:
	beqz	a0, read_bits_end
	lb	a4, (a2)
	addi	a3, a0, -8
	add	a3, a3, s2
	bltz	a3, read_bits_negative
	sll	a4, a4, a3
	or	a1, a1, a4
	addi	a2, a2, 1
	mv	s2, zero
	mv	a0, a3
	b	read_bits_loop
read_bits_negative:
	sub	a3, zero, a3
	srl	a4, a4, a3
	or	a1, a1, a4
	add	a5, a0, s2
	srli	a6, a5, 3
	add	a2, a2, a6
	andi	s2, a5, 7
read_bits_end:
	sub	s1, a2, s0
	addi	a0, a0, 1
	sll	a0, a0, a7
	addi	a0, a0, -1
	and	a0, a1, a0
	ret
	
	
compress:
	la	a0, origin_table
	li	a1, 1
	mv	t6, ra
	mv	t5, zero
compress_source_loop:
	sb	t5, (a0)
	call	hash_put
	addi	t5, t5, 1
	andi	t5, t5, 0xff
	beqz	t5, compress_source_end
	addi	a0, a0, 1
	b	compress_source_loop
compress_source_end:
	mv	a0, s0
	li	a1, 1
	add	t0, s0, s3
compress_loop:
	add	t5, a0, a1
	beq	t0, t5, compress_end
	mv	t5, a1
	addi	a1, a1, 1
	call	hash_get
	beqz	a2, compress_loop
	mv	a1, t5
	call	hash_get
	
	mv	t2, a0
	mv	t4, a1
	
	li	a0, LZW_BITS
	mv	a1, a3
	call	write_bits
	
	mv	a0, t2
	mv	a1, t4
	
	addi	a1, a1, 1
	call	hash_put
	
	mv	a1, t5
	add	a0, a0, a1
	li	a1, 1
	
	b	compress_loop
compress_end:
	call	hash_get
	li	a0, LZW_BITS
	mv	a1, a3
	call	write_bits
	mv	ra, t6
	ret
	
	
decompress:
	la	a0, origin_table
	li	a1, 1
	mv	t6, ra
	mv	t0, zero
decompress_source_loop:
	sb	t0, (a0)
	call	str_put
	addi	t0, t0, 1
	andi	t0, t0, 0xff
	beqz	t0, decompress_source_end
	addi	a0, a0, 1
	b	decompress_source_loop
decompress_source_end:
	li	a0, LZW_BITS
	call	read_bits
	call	str_get
	mv	t0, a0
	mv	t2, a1
	call	write_str
decompress_loop:
	li	a0, LZW_BITS
	call	can_read
	beqz	a0, decompress_end
	call	read_bits
	call	str_get
	mv	t3, a0
	mv	t4, a1
	ebreak	# 
	beqz	a0, decompress_sc
	
	mv	a2, a0
	mv	a0, t0
	mv	a1, t2
	call	create_entry
	mv	a0, t3
	mv	a1, t4
	call	write_str
	b	decompress_next
decompress_sc:
	mv	a2, t0
	mv	a0, t0
	mv	a1, t2
	call	create_entry
	call	write_str
decompress_next:
	mv	t0, t3
	mv	t2, t4
	b	decompress_loop
decompress_end:
	mv	ra, t6
	ret
	
	
file_err:
	exit_with_str (file_err_str)

file_op_err:
	exit_with_str (file_op_str)

input_empty:
	exit_with_str (no_input)
