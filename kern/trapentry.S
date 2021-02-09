/* See COPYRIGHT for copyright information. */

#include <inc/mmu.h>
#include <inc/memlayout.h>
#include <inc/trap.h>

#include <kern/picirq.h>


###################################################################
# exceptions/interrupts
###################################################################

/* TRAPHANDLER defines a globally-visible function for handling a trap.
 * It pushes a trap number onto the stack, then jumps to _alltraps.
 * Use TRAPHANDLER for traps where the CPU automatically pushes an error code.
 *
 * You shouldn't call a TRAPHANDLER function from C, but you may
 * need to _declare_ one in C (for instance, to get a function pointer
 * during IDT setup).  You can declare the function with
 *   void NAME();
 * where NAME is the argument passed to TRAPHANDLER.
 */
#define TRAPHANDLER(name, num)						\
	.globl name;		/* define global symbol for 'name' */	\
	.type name, @function;	/* symbol type is function */		\
	.align 2;		/* align function definition */		\
	name:			/* function starts here */		\
	pushl $(num);							\
	jmp _alltraps

/* Use TRAPHANDLER_NOEC for traps where the CPU doesn't push an error code.
 * It pushes a 0 in place of the error code, so the trap frame has the same
 * format in either case.
 */
#define TRAPHANDLER_NOEC(name, num)					\
	.globl name;							\
	.type name, @function;						\
	.align 2;							\
	name:								\
	pushl $0;							\
	pushl $(num);							\
	jmp _alltraps

.text



/*
 * Lab 3: Your code here for generating entry points for the different traps.
 */
	TRAPHANDLER_NOEC(traphd0,0)
	TRAPHANDLER_NOEC(traphd1,1)
	TRAPHANDLER_NOEC(traphd2,2)
	TRAPHANDLER_NOEC(traphd3,3)
	TRAPHANDLER_NOEC(traphd4,4)
	TRAPHANDLER_NOEC(traphd5,5)
	TRAPHANDLER_NOEC(traphd6,6)
	TRAPHANDLER_NOEC(traphd7,7)
	TRAPHANDLER(traphd8,8)
	TRAPHANDLER_NOEC(traphd9,9)
	TRAPHANDLER(traphd10,10)
	TRAPHANDLER(traphd11,11)
	TRAPHANDLER(traphd12,12)
	TRAPHANDLER(traphd13,13)
	TRAPHANDLER(traphd14,14)
	TRAPHANDLER_NOEC(traphd16,16)

	TRAPHANDLER_NOEC(trap_system_call,48)

/*
 * Lab 3: Your code here for _alltraps
 */

_alltraps:
	pushl %ds
	pushl %es
	pushal //压入eax 等通用寄存器
	pushl $GD_KD
	pushl $GD_KD
	popl %ds
	popl %es
	pushl %esp //把trapframe的地址压入栈传给trap,指向trapframe的起始地址
	call trap
