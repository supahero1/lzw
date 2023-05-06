	.eqv	CHUNK_SIZE,	4096	# how much to read from file in one go
	.eqv	FILENAME_SIZE,	256	# max file name length
	.eqv	DICT_SIZE,	65536	# max entries in the LZW dictionary
	.eqv	VARUINT_SIZE,	7	# how many bits are used in the output
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
	mv	s1, a1		# s1 = src len
	
	li	s4, DICT_SIZE	# s4 = dict length
	slli	s5, s4, 3	# s5 = byte dict size
	mv	a0, s5
	li	a7, SBRK
	ecall
	mv	s3, a0		# s3 = dict ptr
	add	t0, a0, a1
memzero_loop:
	beq	a0, t0, memzero_end
	sw	zero, (a0)
	addi	a0, a0, 8	# only zero ptr in the struct
memzero_end:

	la	a0, pick_mode
	li	a7, PRINTS
	ecall
	li	a7, READI
	ecall
	mv	s2, a0		# s2 = LZW mode
	
	li	s6, 0x01000193	# s6 = FNV_1a magic number
	
	la	a0, pick_file
	li	a1, 4
	call	hash_get
	li	a7, PRINTI
	ecall
	
	la	a0, pick_file
	li	a1, 4
	call	hash_put
	
	la	a0, pick_file
	li	a1, 4
	call	hash_get
	li	a7, PRINTI
	ecall

	la	a0, out_file
	li	a7, PRINTS
	ecall
	la	a0, filename
	li	a1, FILENAME_SIZE
	li	a7, READS
	ecall
	call	sanitize_str
	mv	a1, s0
	mv	a2, s1
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
	mul	a7, a7, s6
	b	fnv_1a_loop
fnv_1a_end:
	remu	a7, a7, s4
	slli	a2, a7, 3
	add	a3, a2, s3
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
	addi	a2, a2, 8
	remu	a2, a2, s5
	add	a3, a2, s3
	b	hash_put_loop
hash_put_end:
	sw	a0, (a3)
	sw	a1, 4(a3)
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
	addi	a2, a2, 8
	remu	a2, a2, s5
	add	a3, a2, s3
	b	hash_get_loop
	
hash_get_end:	# success
	mv	a0, zero
	ret
hash_get_no_end:
	li	a0, 1
	ret
	
	
file_err:
	exit_with_str (file_err_str)

file_op_err:
	exit_with_str (file_op_str)
