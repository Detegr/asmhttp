section .data
		errmsg: db "Error", 10
	errlen: equ $-errmsg
	acceptmsg: db "Connection accepted!", 10
	acceptlen: equ $-acceptmsg
	childmsg: db "Child process", 10
	childlen: equ $-childmsg
	sys_socketcall: dd 102

	ok_header: db "HTTP/1.1 200 OK", 13, 10, "Content-Type: text/html", 13, 10, "Content-Length: 12", 13, 10, 13, 10, "<h1>foo</h1>", 13, 10, 13 ,10
	ok_len: equ $-ok_header

	HTTP_MAX: dd 8192
section .bss
	sock_fd resd 1
	recvbuf resb 8192
section .text
global _start

_start:
	; Inform kernel that it should clean up our dead children
	mov eax, 48 ; sys_signal
	mov ebx, 17 ; SIGCHLD
	mov ecx, 1  ; SIG_IGN
	int 0x80

	call socket
	call bind
	call listen
	call loop
	call close

	mov eax, 1
	mov ebx, 0
	int 0x80

socket:
	push ebp
	mov ebp, esp
	sub esp, 32

	mov dword [ebp-12], 2 ; AF_INET
	mov dword [ebp-8], 1 ; SOCK_DGRAM
	mov dword [ebp-4], 0

	mov eax, [sys_socketcall] ; sys_socketcall
	mov ebx, 1 ; socketcall(socket)
	lea ecx, [ebp-12] ;
	int 0x80

	cmp eax, 0
	jle fail

	mov dword [sock_fd], eax

	; SYS_SETSOCKOPT == 14


	mov dword [ebp-32], eax
	mov dword [ebp-28], 1 ; SOL_SOCKET
	mov dword [ebp-24], 2 ; SO_REUSEADDR
	mov dword [ebp-4], 1

	; void* optval
	lea eax, [ebp-4]
	mov dword [ebp-20], eax
	mov dword [ebp-16], 4 ; optlen
	
	mov eax, [sys_socketcall]
	mov ebx, 14 ; SYS_SETSOCKOPT
	lea ecx, [ebp-32]
	int 0x80

	add esp, 32

	cmp eax, 0
	jne fail

	leave
	ret

bind:
	push ebp
	mov ebp, esp
	sub esp, 32
	mov word [ebp-32], 2 ; AF_INET
	xor eax, eax
	mov eax, 8080 ; port
	ror ax, 8 ; rotate port to network byte order
	mov word [ebp-30], ax
	mov dword [ebp-28], 0 ; INADDR_ANY
	mov dword [ebp-24], 0 ; sin_zero
	mov dword [ebp-20], 0 ; sin_zero

	mov eax, [sock_fd]
	mov dword [ebp-16], eax ; fd
	lea eax, [ebp-32]
	mov [ebp-12], eax ; sockaddr ptr
	mov dword [ebp-8], 16 ; sizeof(sockaddr)

	mov eax, [sys_socketcall]
	mov ebx, 2; sys_bind
	lea ecx, [ebp-16] ; args ptr
	int 0x80

	cmp eax, 0
	jne fail

	add esp, 16
	leave
	ret

listen:
	push ebp
	mov ebp, esp
	sub esp, 8

	; set up arg[0] (fd)
	mov eax, [sock_fd]
	mov [ebp-8], eax

	; set up arg[1]
	mov dword [ebp-4], 10 ; backlog of 10 connections

	mov dword eax, [sys_socketcall]
	mov ebx, 4 ; sys_listen
	lea ecx, [ebp-8]
	int 0x80

	add esp, 8
	leave
	ret

; Close fd pushed to stack
close:
	pop ebx
	mov eax, 6 ; sys_close
	int 0x80
	ret
sleep:
	push ebp
	mov ebp, esp
	sub esp, 8

	mov [esp-8], eax ; seconds
	mov dword [esp-4], 0 ; useconds
	mov eax, 162 ; sys_nanosleep
	lea ebx, [esp-8]
	mov ecx, 0
	int 0x80

	add esp, 8
	leave
	ret

loop:
	push ebp
	mov ebp, esp
	sub esp, 80

	mov eax, [sock_fd]
	mov [ebp-16], eax
	mov dword [ebp-12], 0
	mov dword [ebp-8], 0
	mov dword [ebp-4], 0

	mov eax, [sys_socketcall]
	mov ebx, 5 ; accept
	lea ecx, [ebp-16]
	int 0x80
	
	cmp eax, 0
	jle fail

	push eax ; store accepted fd

	mov [ebp-80], ebx
	mov [ebp-76], ecx
	mov [ebp-72], edx
	mov [ebp-68], esi
	mov [ebp-64], edi
	mov [ebp-60], ebp
	mov [ebp-56], eax
	mov [ebp-52], ds
	mov [ebp-48], es
	mov [ebp-44], fs
	mov [ebp-40], gs
	mov [ebp-36], eax
	mov dword [ebp-32], 0 ; eip
	mov [ebp-28], cs
	mov dword [ebp-24], 0 ; eflags
	mov [ebp-20], esp
	mov [ebp-16], ss

	mov eax, 2 ; sys_fork
	lea ebx, [ebp-80]
	int 0x80

	cmp eax, 0
	jl fail
	je child
	jg accept_new

	leave
	ret

child:
	pop ecx ; pop accepted fd to ebx
	add esp, 80
	leave

	push ebp
	mov ebp, esp
	sub esp, 16

	mov eax, [sys_socketcall]
	mov ebx, 10 ; sys_recv

	mov [ebp-16], ecx ; fd
	mov dword [ebp-12], recvbuf
	mov ecx, [HTTP_MAX]
	mov [ebp-8], ecx
	mov dword [ebp-4], 0
	lea ecx, [ebp-16]
	int 0x80

	cmp eax, 0
	jl fail
	mov ebx, [ebp-16]
	push ebx
	je close

	mov dword [ebp-12], ok_header
	mov dword [ebp-8], ok_len
	mov eax, [sys_socketcall]
	mov ebx, 11 ; sys_send
	lea ecx, [ebp-16]
	int 0x80

	cmp eax, 0
	jl fail
	mov ebx, [ebp-16]

	push ebx
	call close

	;mov edx, eax
	;mov eax, 4 ; sys_write
	;mov ebx, 1 ; stdout
	;mov ecx, recvbuf
	;int 0x80

	mov eax, 1
	mov ebx, 0
	int 0x80

accept_new:
	mov eax, 4
	mov ebx, 1
	mov ecx, acceptmsg
	mov edx, acceptlen
	int 0x80

	add esp, 80

	leave
	jmp loop

fail:
	push eax
	mov eax, 4
	mov ebx, 1
	mov ecx, errmsg
	mov edx, errlen
	int 0x80

	mov eax, 1
	pop ebx
	mov ecx, 256
	sub ecx, ebx
	mov ebx, ecx
	int 0x80
