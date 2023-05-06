	.eqv	CHUNK_SIZE,	4096	# how much to read from file in one go
	.eqv	FILENAME_SIZE,	256	# max file name length
	.eqv	DICT_SIZE,	65536	# max entries in the LZW dictionary
	.eqv	OUT_BITS,	16	# how many bits to use per output code
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
seed:		.space	2
no_input:	.asciz	"The input is empty, nothing to do.\n"


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
	addi	a0, a0, 12	# only zero ptr in the struct
memzero_end:
	mv	s6, zero	# s6 = dict index
	
	# s11 = return address save
	
	li	s10, CHUNK_SIZE	# s10 = output total size
	mv	a0, s10
	li	a7, SBRK
	ecall
	mv	s7, a0		# s7 = output buffer
	mv	s8, zero	# s8 = output used length
	mv	s9, zero	# s9 = output bit index

	call	source

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
	lb	t1, (t0)
	xori	t1, t1, 0x0a
	beqz	t1, sanitize_end
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
	mv	t1, a0
	
	mv	a0, t0
	mv	a1, t1
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
	
	mv	a0, t1
	sub	a1, a1, t1
	add	t0, a0, a1
	sb	zero, (t0)
	ret
	
	
write_file:	# a0 = file name, a1 = buffer to write, a2 = buffer length
	mv	t1, a1
	
	li	a1, 1
	li	a7, OPEN
	ecall
	blt	a0, zero, file_err
	mv	t0, a0
	
	mv	a1, t1
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
	lb	a4, (a5)
	sb	zero, (a5)
	mv	a3, a0
fnv_1a_loop:
	lb	a6, (a3)
	beqz	a6, fnv_1a_end
	addi	a3, a3, 1
	xor	a7, a7, a6
	mul	a7, a7, a2
	b	fnv_1a_loop
fnv_1a_end:
	li	a6, 12
	mul	a7, a6, a7
	remu	a2, a7, s5
	add	a3, a2, s4
	sb	a4, (a5)
	ret
	
	
hash_put:	# a0 = data ptr, a1 = length
	mv	s11, ra
	call	fnv_1a
	mv	ra, s11
hash_put_loop:
	lw	t0, (a3)
	bnez	t0, hash_put_cont
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
	lw	t0, (a3)
	beqz	t0, hash_get_no_end
	lw	t1, 4(a3)
	bne	t1, a1, hash_get_next
	add	t2, a0, a1
	mv	t3, a0
hash_get_memcmp:
	lb	t4, (t0)
	lb	t5, (t3)
	sub	t4, t4, t5
	bnez	t4, hash_get_next
	addi	t0, t0, 1
	beq	t0, t2, hash_get_end
	addi	t3, t3, 1
	b	hash_get_memcmp

hash_get_next:
	addi	a2, a2, 12
	remu	a2, a2, s5
	add	a3, a2, s4
	b	hash_get_loop
	
hash_get_end:	# success
	mv	a0, zero
	lw	a1, 8(a3)
	ret
hash_get_no_end:
	li	a0, 1
	ret
	
	
write_bits:	# a0 = bits, a1 = number
	add	a2, s7, s8
	
	add	a3, s9, a0
	srli	a3, a3, 3
	add	a3, a3, s8
	bgtu	a3, s10, write_bits_resize
	b	write_bits_loop
write_bits_resize:
	mv	a3, a1
	li	a1, CHUNK_SIZE
	add	s10, s10, a1
	li	a7, SBRK
	ecall
	mv	a1, a3
	
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
	
	
source:
	la	a0, seed
	li	a1, 1
	mv	t5, ra
	mv	t6, zero
source_loop:
	sb	t6, (a0)
	call	hash_put
	addi	t6, t6, 1
	andi	t6, t6, 0xff
	beqz	t6, source_end
	b	source_loop
source_end:
	mv	ra, t5
	ret
	
	
compress:
	ebreak
	mv	a0, s0
	li	a1, 1
	add	t0, s0, s3
	mv	t6, ra
compress_loop:
	add	t1, a0, a1
	beq	t0, t1, compress_end
	addi	a1, a1, 1
	call	hash_get		# TODO separate registers
	beqz	a0, compress_loop
	addi	a1, a1, -1
	call	hash_get
	mv	t2, a0
	li	a0, OUT_BITS
	call	write_bits
	mv	a0, t2
	addi	a1, a1, 1
	call	hash_put
	b	compress_loop
compress_end:
	call	hash_get
	li	a0, OUT_BITS
	call	write_bits
	mv	ra, t6
	ret
	
	
decompress:
	ret
	
	
file_err:
	exit_with_str (file_err_str)

file_op_err:
	exit_with_str (file_op_str)
	
input_empty:
	exit_with_str (no_input)
