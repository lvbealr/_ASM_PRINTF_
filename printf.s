global myPrintf

section .text

; ______________________________________________________________________ ;
; Assumed: rdx - string length                                           ;
;          rsi - pointer to symbols sequence                             ;
; ______________________________________________________________________ ;

%macro printSymbols_ 0
    cmp rdx, 0                  ; check string length in rdx
    je %%endPrintSymbols        ; no data to be printed

    push rdx                    ; save string length in stack
    push rax                    ; save rax in stack (for buffer size)
    push rbx                    ; save rbx (temp symbol storage)

    mov rax, [BUFFER_SIZE]      ; rax = buffer size

    %%writeSymbols:
        cmp rax, BUFFER_CAPACITY
        jb %%loop

        call flushBuffer        ; if size >= capacity => print symbols
    %%loop:
        mov rbx, [rsi]
        mov [BUFFER + rax], rbx ; save byte into a buffer

        inc rsi                 ; move to
        inc rax                 ; next symbol

        dec rdx                 ; one symbol was written, decrease length

        jnz %%writeSymbols

        mov [BUFFER_SIZE], rax  ; save buffer size

        pop rbx                 ; restore registers
        pop rax
        pop rdx

    %%endPrintSymbols:
%endmacro

myPrintf:
    push rbp                    ; save rbp
    mov rbp, rsp                ; create stack frame for printf local variables

    sub rsp, 48

    ; SYSTEM V AMD64 ABI (unix)
    ; first six args in rdi, rsi, rdx, rcx, r8, r9
    ; extra args in stack
    ; rbx, rbp, r12-r15          are callee-saved
    ; rdi, rsi, rdx, rcx, r8, r9 are caller-saved

                                ;_________________________; <---- rbp
    mov [rbp - 8],  rdi         ;_________ rdi ___________; <---- format string
    mov [rbp - 16], rsi         ;_________ rsi ___________; <---- first arg
    mov [rbp - 24], rdx         ;_________ rdx ___________; <---- second arg
    mov [rbp - 32], rcx         ;_________ rcx ___________; <---- third arg
    mov [rbp - 40], r8          ;__________ r8 ___________; <---- fourth arg
    mov [rbp - 48], r9          ;__________ r9 ___________; <---- rsp (fifth arg)
                                ;_________________________;
    mov rsi, rdi
    mov rbx, 1                  ; current argument index (starting from 1st)

    .loop:
        call strlenToTerminator
        printSymbols_

        cmp byte [rsi], 0x00    ; if null-terminator ?
        jne .recognizeSpecificator

        jmp .return

    .recognizeSpecificator:
        inc rsi

        cmp byte [rsi], 'a'     ; specificators only: %(b|c|d|o|s|x)
        jb .printSymbol

        cmp byte [rsi], 'x'
        ja .printSymbol

        xor rax, rax
        mov al, [rsi]           ; read specificator

        lea rax, [(rax - 'a')]
                                ; rax = ascii code of specificator symbol

        jmp [specificatorsTable + rax * 8]
                                ; jump to desired label

        jmp .loop

        .printSymbol:
            call printSymbol    ; unknown spec processing
            jmp .loop           ; print % and next symbol

        .printBinary:
            call getArgument    ; put next arg into rax

            push rbx
            mov rbx, 0x01       ; mask
            mov rcx, 1          ; shift (2^1)
            call printNumber
            pop rbx

            jmp .loop

        .printChar:
           call getArgument     ; put next arg into rax
           call printChar

           jmp .loop

        .printUnsigned:
            call getArgument    ; put next arg into rax
            call printUnsigned

            jmp .loop

        .printSigned:
            call getArgument    ; put next arg into rax
            call printSigned

            jmp .loop

        .printOctal:
            call getArgument    ; put next arg into rax

            push rbx
            mov rbx, 0x07       ; mask
            mov rcx, 3          ; shift (2^3)
            call printNumber
            pop rbx

            jmp .loop

        .printString:
            call getArgument    ; put next arg into rax
            call printString

            jmp .loop

        .printHex:
            call getArgument    ; put next arg into rax

            push rbx
            mov rbx, 0x0f       ; mask
            mov rcx, 4          ; shift (2^4)
            call printNumber
            pop rbx

            jmp .loop

        .storePrintedSymbols:
            call getArgument    ; put next arg into rax
            mov rdx, [PRINTED_SYMBOLS]

            mov [rax], rdx
            inc rsi             ; skip spec symbol

            jmp .loop

        .return:
            mov rax, [BUFFER_SIZE]
            call flushBuffer

            mov rdi, [rbp - 8]          ; restore regs
            mov rsi, [rbp - 16]
            mov rdx, [rbp - 24]
            mov rcx, [rbp - 32]
            mov r8,  [rbp - 40]
            mov r9,  [rbp - 48]

            mov rax, [rbp]
            mov [SAVED_RBP], rax        ; save pushed rbp

            mov rax, [rbp + 8]
            mov [SAVED_RET], rax        ; save pushed return address

            lea rsp, [rbp + 0x10]       ; clean stack (rbp + 16 bytes for rbp and ret)

            push qword [SAVED_RET]      ; restore return address
            push qword [SAVED_RBP]      ; restore old rbp

            mov rbp, rsp

            mov rax, [PRINTED_SYMBOLS]

            leave                       ; clean stack frame <=> mov rsp, rbp; pop rbp
            ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rbx - argument index                       ;
;              rbp set in myPrintf                        ;
; Return:      rax - argument, rbx - next arg index       ;
; Destroy:     None                                       ;
; _______________________________________________________ ;
getArgument:
    inc rbx

    mov rax, rbx        ; get arg index into rax
    shl rax, 3          ; rax = rbx * 8

    cmp rax, 6 * 8      ; check stack
    ja .stackArgument

    neg rax             ; invert the offset to access saved regs
    add rax, rbp
    mov rax, [rax]      ; get arg from stack (placed after call)
    ret

    .stackArgument:
        sub rax, 6 * 8  ; 6 registers in stack frame
        add rax, 0x08   ; rbp and ret size

        add rax, rbp
        mov rax, [rax]

        ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rax - number                               ;
;              rbx - bit mask for one digit               ;
;              rcx - shift in bits                        ;
; Return:      None                                       ;
; Destroy:     rdx, r8, rax, rcx, rdi, [PRINTF_BUFFER]    ;
; _______________________________________________________ ;
printNumber:
    mov r8, rcx         ; save shift into r8

    mov rdi, PRINTF_BUFFER
    mov rdx, rax        ; save number into rdx
    mov rcx, 64         ; register size

    cmp r8, 3           ; check hex
    jne .skipZero

    mov rcx, 66         ; add two magic bits

    .skipZero:
        cmp cl, 0
        je .writeZero

        sub rcx, r8     ; decrease position
        mov rax, rdx    ; restore number into rax
        shr rax, cl

        and rax, rbx    ; use mask to get digit

        cmp rax, 0
        je .skipZero    ; skip if zero

        add rcx, r8     ; return to skipped position

    .printDigit:
        sub rcx, r8     ; decrease position
        mov rax, rdx    ; restore number into rax
        shr rax, cl

        and rax, rbx    ; get curr digit

        mov byte al, [rax + DIGITS]
                        ; digit to char
        mov byte [rdi], al
        inc rdi         ; write digit (char) into buffer

        cmp rcx, 0
        ja .printDigit  ; print next digit

    .writeNumber:
        push rsi        ; save rsi

        mov rdx, rdi    ; calculate string length
        sub rdx, PRINTF_BUFFER
                        ; length = end pointer - start pointer (buffer)
        mov rsi, PRINTF_BUFFER

        printSymbols_

        pop rsi         ; skip spec symbol
        inc rsi

        ret

    .writeZero:
        mov byte [rdi], '0'
        mov byte [rdi + 1], 0
        add rdi, 2

        jmp .writeNumber

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rax - char symbol                          ;
; Return:      None                                       ;
; Destroy:     rdx, [PRINTF_BUFFER]                       ;
; _______________________________________________________ ;
printChar:
    push rsi
    mov [PRINTF_BUFFER], rax    ; save sym from rax into buffer
    mov rsi, PRINTF_BUFFER      ; set rsi to buffer

    call printSymbol

    pop rsi
    inc rsi                     ; skip spec symbol

    ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rax - number (unsigned)                    ;
; Return:      None                                       ;
; Destroy:     rdx, rdi, [PRINTF_BUFFER]                  ;
; _______________________________________________________ ;
printUnsignedToBuffer:
    push rbx

    mov rbx, 10
            ; decimal
    lea rdi, [PRINTF_BUFFER + PRINTF_BUFFER_SIZE - 1]
            ; end of buffer pointer
    .printDigit:
        xor rdx, rdx    ; remainder = 0

        div rbx         ; remainder to rdx, quotient to rax

        mov byte dl, [DIGITS + rdx]
                        ; remainder to symbol
        mov byte [rdi], dl
                        ; write into a buffer

        dec rdi         ; move from right to left

        cmp rax, 0
        jne .printDigit

    .return:
        pop rbx
        ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rax - number (unsigned)                    ;
; Return:      rsi - next string char                     ;
; Destroy:     rdx, rdi, [PRINTF_BUFFER]                  ;
; _______________________________________________________ ;
printUnsigned:
    call printUnsignedToBuffer
                        ; number to string

    push rsi

    lea rsi, [rdi + 1]  ; set rsi to start of string
    mov rdx, PRINTF_BUFFER + PRINTF_BUFFER_SIZE - 1
                        ; rdx = end of buffer
    sub rdx, rdi        ; calculate string length
    printSymbols_

    pop rsi
    inc rsi             ; skip spec symbol

    ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rax - number                               ;
; Return:      rsi - next string char                     ;
; Destroy:     rdx, rdi, r8 [PRINTF_BUFFER]               ;
; _______________________________________________________ ;
printSigned:
    xor r8, r8          ; flag for signed
    test rax, rax       ; check negative

    jns .printBuffer

    mov r8, 1           ; set flag for signed
    neg rax             ; rax ( < 0) = -rax ( > 0)

    .printBuffer:
        call printUnsignedToBuffer

        cmp r8, 0       ; check flag for signed
        je .writeNumber

        mov byte [rdi], '-'
        dec rdi

    .writeNumber:
        push rsi

        lea rsi, [rdi + 1]
        mov rdx, PRINTF_BUFFER + PRINTF_BUFFER_SIZE - 1
                        ; end of buffer
        sub rdx, rdi    ; string length
        printSymbols_

        pop rsi
        inc rsi         ; skip spec symbol

        ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rax - string pointer                       ;
; Return:      None                                       ;
; Destroy:     rdx, [PRINTF_BUFFER]                       ;
; _______________________________________________________ ;
printString:
    push rsi

    mov rsi, rax        ; rsi -> string offset
    call strlen

    printSymbols_

    pop rsi
    inc rsi             ; skip spec symbol

    ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rsi - string address                       ;
;              rdx - string length                        ;
; Return:      rsi - next symbol                          ;
; Destroy:     rdx                                        ;
; _______________________________________________________ ;
printSymbol:
    push rdx             ; save rdx

    mov rdx, 1           ; string length = 1
    printSymbols_        ; syscall

    pop rdx

    ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rax - current buffer size                  ;
; Return:      rax = 0                                    ;
; Destroy:     None                                       ;
; _______________________________________________________ ;
flushBuffer:
    push rsi                    ; save rsi and rdx
    push rdx

    mov rdx, rax                ; rdx = buffer size
    mov rsi, BUFFER             ; rsi = buffer offset
    call writeBuffer

    xor rax, rax
    mov qword [BUFFER_SIZE], 0  ; buffer was flushed

    pop rdx
    pop rsi                     ; restore rdx and rsi
    ret

; _______________________________________________________ ;
; Description: TODO                                       ;
; Assumed:     rsi - string pointer                       ;
;              rdx - strlen                               ;
; Return:      rsi - next symbol, PRINTED_SYMBOLS += rdx  ;
; Destroy:     None                                       ;
; _______________________________________________________ ;
writeBuffer:
    push rax                    ; save rax and rdi
    push rdi

    add [PRINTED_SYMBOLS], rdx  ; increase printed symbols counter

    mov rax, 0x01               ; syscall (write - 0x01)
    mov rdi, 1                  ; stdout
    syscall

    add rsi, rdx                ; increment string pointer

    pop rdi
    pop rax

    ret

strlen:
    mov rdx, 0

    .loop:
        cmp byte [rsi + rdx], 0x0
        je .return

        inc rdx
        jmp .loop

    .return:
        ret

; _______________________________________________________ ;
; Description: find  string length to '%' (or to '\0')    ;
; Assumed:     None                                       ;
; Return:      rdx - string length to '%' (or to '\0')    ;
;              rsi - next symbol posiiton                 ;
; Destroy:     None                                       ;
; _______________________________________________________ ;
strlenToTerminator:
    xor rdx, rdx

    .loop:
        cmp byte [rsi + rdx], '%'  ; check if '%'
        je .endLoop

        cmp byte [rsi + rdx], 0x0  ; check if '\0'
        je .endLoop

        inc rdx

        jmp .loop

    .endLoop:
        ret

; ################################################################################################# ;

section .data

DIGITS                                 db "0123456789abcdef"

SAVED_RBP                              dq  0
SAVED_RET                              dq  0

PRINTED_SYMBOLS                        dq  0

BUFFER_SIZE                            dq  0
BUFFER_CAPACITY                        equ 256
BUFFER times BUFFER_CAPACITY           db  0

PRINTF_BUFFER_SIZE                     equ 64
PRINTF_BUFFER times PRINTF_BUFFER_SIZE db  0

; ________________________________________________________ ;
; Contains the addresses of the labels to jump to          ;
; ________________________________________________________ ;

specificatorsTable:
    dq myPrintf.printSymbol                      ;
    dq myPrintf.printBinary                      ; %b - binary number
    dq myPrintf.printChar                        ; %c - char symbol
    dq myPrintf.printSigned                      ; %d - decimal number
    times ('n' - 'd' - 1) dq myPrintf.printSymbol    ;
    dq myPrintf.storePrintedSymbols              ; %n - store printed symbols
    dq myPrintf.printOctal                       ; %o - octal number
    times ('s' - 'o' - 1) dq myPrintf.printSymbol    ;
    dq myPrintf.printString                      ; %s - char array (string)
    dq myPrintf.printSymbol                      ;
    dq myPrintf.printUnsigned                    ; %u - unsigned number
    times ('x' - 'u' - 1) dq myPrintf.printSymbol    ;
    dq myPrintf.printHex                         ; %x - hex number
