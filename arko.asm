	.eqv	CHUNK_SIZE,	4096	# how much to read from file in one go
	.eqv	FILENAME_SIZE,	256	# max file name length
	.eqv	DICT_SIZE,	65536	# max entries in the LZW dictionary
	.eqv	VARUINT_SIZE,	7	# how many bits are used in the output
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
	mv	s1, a0
	mv	s2, a1
	
	la	a0, out_file
	li	a7, PRINTS
	ecall
	
	la	a0, filename
	li	a1, FILENAME_SIZE
	li	a7, READS
	ecall
	
	call	sanitize_str
	
	mv	a1, s1
	mv	a2, s2
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
	
	
fnv_1a:		# a0 = string
	li	t0, 0x811c9dc5
	li	t1, 0x01000193
fnv_1a_loop:
	lb	t2, (a0)
	beqz	t2, fnv_1a_end
	addi	a0, a0, 1
	xor	t0, t0, t2
	mul	t0, t0, t1
	b	fnv_1a_loop
fnv_1a_end:
	mv	a0, t0
	ret
	
	
	
	
file_err:
	exit_with_str (file_err_str)

file_op_err:
	exit_with_str (file_op_str)
