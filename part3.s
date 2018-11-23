				.include	"address_map_arm.s"
				.include	"interrupt_ID.s"

/* ********************************************************************************
 * This program demonstrates use of interrupts with assembly language code. 
 * The program responds to interrupts from the pushbutton KEY port in the FPGA.
 *
 * The interrupt service routine for the pushbutton KEYs indicates which KEY has 
 * been pressed on the HEX0 display.
 ********************************************************************************/


	//timer isr
 	.global counter
	counter: .word 0

	//part3keyboard isr
	.global buffer
	buffer: .word 0

	.global flag
	flag: .word 0

				.section .vectors, "ax"

				B 			_start					// reset vector
				B 			SERVICE_UND				// undefined instruction vector
				B 			SERVICE_SVC				// software interrrupt vector
				B 			SERVICE_ABT_INST		// aborted prefetch vector
				B 			SERVICE_ABT_DATA		// aborted data vector
				.word 	0							// unused vector
				B 			SERVICE_IRQ				// IRQ interrupt vector
				B 			SERVICE_FIQ				// FIQ interrupt vector

				.text
				.global	_start
_start:		
				/* Set up stack pointers for IRQ and SVC processor modes */
				MOV		R1, #0b11010010					// interrupts masked, MODE = IRQ
				MSR		CPSR_c, R1							// change to IRQ mode
				LDR		SP, =A9_ONCHIP_END - 3			// set IRQ stack to top of A9 onchip memory
				/* Change to SVC (supervisor) mode with interrupts disabled */
				MOV		R1, #0b11010011					// interrupts masked, MODE = SVC
				MSR		CPSR, R1								// change to supervisor mode
				LDR		SP, =DDR_END - 3					// set SVC stack to top of DDR3 memory

				BL			CONFIG_GIC							// configure the ARM generic interrupt controller

				// write to the pushbutton KEY interrupt mask register
				LDR		R0, =KEY_BASE						// pushbutton KEY base address
				MOV		R1, #0xF								// set interrupt mask bits
				STR		R1, [R0, #0x8]						// interrupt mask register is (base + 8)

				// enable IRQ interrupts in the processor
				MOV		R0, #0b01010011					// IRQ unmasked, MODE = SVC
				MSR		CPSR_c, R0
				
				//timer init
				LDR R1, =MPCORE_PRIV_TIMER		
				LDR R3, =100000000 			// half
				STR R3, [R1] 				
				MOV R3, #0b111		
				STR R3, [R1, #0x8]	

CHAR:
				BL RCHAR
				BL CHKCHAR
				BL WCHAR
				B CHAR
				
RCHAR:		
				//read char
				//JTAG UART
				LDR R1,=JTAG_UART_BASE
				//JTAG register load
				LDR R0,[R1]
				//data check
				LDR R3,=0x8000
				ANDS R2,R0,R3
				BEQ NODATA
				//char ret
				LDR R3,=0x00FF
				AND R0,R0,R3
				BX LR

WCHAR:
				//write char
				//JTAG UART
				LDR R1,=JTAG_UART_BASE
				//JTAG register load
				LDR R2,[R1,#4]
				//1s for bitwise and
				LDR R3,=0xFFFF
				//bitwise and
				ANDS R2,R2,R3
				BEQ BXOUT
				//write char
				STR R0,[R1]
				B BXOUT

CHKCHAR:
				//check char
				//check R0 for flag 
				CMP R0,#0
				//keep checking until flag is high
				BEQ CHAR
				B BXOUT

NODATA:
				MOV R0,#0

IDLE:
				LDR R10,=flag
				LDR R8,[R10,#0]
				CMP R8,#1
				//if char flag high then
				BNE	IDLE  // main program simply idles
				B BUFF

BUFF:			
				LDR R5,=buffer
				LDR R0,[R5,#0]

				BL WCHAR

				MOV R9,#0
				STR R9,[R10,#0]

				B	IDLE

BXOUT:
				BX LR


/* Define the exception service routines */

/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:
    			B SERVICE_UND 
 
/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:			
    			B SERVICE_SVC 

/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:
    			B SERVICE_ABT_DATA 

/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:
    			B SERVICE_ABT_INST 
 
/*--- IRQ ---------------------------------------------------------------------*/
SERVICE_IRQ:
    			PUSH		{R0-R7, LR}
    
    			/* Read the ICCIAR from the CPU interface */
    			LDR		R4, =MPCORE_GIC_CPUIF
    			LDR		R5, [R4, #ICCIAR]				// read from ICCIAR
				
				//char isr
				LDR R7, =buffer
				LDR R1, =JTAG_UART_BASE
				
				LDRB R2, [R1]
				STR R2, [R7, #0]

				LDR R8, =flag
				MOV R2, #1
				STR R2, [R8,#0]
				
				//check if key_isr
				CMP R5, #KEYS_IRQ
				//key_isr
				BEQ FPGA_IRQ1_HANDLER
				//else timer_isr
				B TIMER_ISR

TIMER_ISR:		
				LDR R6, =LEDR_BASE //init red LEDs
				LDR R9, =counter //counter global val

				LDR R2, [R9, #0]
				ADD R2, R2, #1 //add 1 to counter
				STR R2, [R9,#0]

				STR R2, [R6]

				//bye
				B EXIT_IRQ

FPGA_IRQ1_HANDLER:
    			CMP		R5, #KEYS_IRQ
UNEXPECTED:		BNE		UNEXPECTED    					// if not recognized, stop here
    
    			BL			KEY_ISR
EXIT_IRQ:
    			/* Write to the End of Interrupt Register (ICCEOIR) */
    			STR		R5, [R4, #ICCEOIR]			// write to ICCEOIR
    
    			POP		{R0-R7, LR}
    			SUBS		PC, LR, #4

/*--- FIQ ---------------------------------------------------------------------*/
SERVICE_FIQ:
    			B			SERVICE_FIQ 

				.end   