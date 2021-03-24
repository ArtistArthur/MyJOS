# MyJOS

## Introduction
lab1的内容或者目的：
* 熟悉x86的汇编语言，搭建环境：下载make qemu等，熟悉PC的开机流程
* examine the boot loader for 6.828 kernel
* initial template for 6.828 kernel ,named JOS
<!--more-->

### a. 搭建环境：git clone qemu
* 完全参照 https://www.cnblogs.com/gatsby123/p/9746193.html
之前用的其他的博客但是没搞好，这个博客解决了  
* 还遇到一个头文件缺失的问题: https://github.com/Ebiroll/qemu_esp32/issues/12 通过添加头文件通过了
学到的东西：  
* 知道了qemu是个跑在linux上的模拟器，可以模拟出各种硬件状态。在这个实验中，qemu的作用是模拟出i386的环境，因为这个实验写出的操作系统是跑在i386上的。

### b. 提交作业
当完成代码后，可以在lab下 make grade,获得评分。  
## Part1：Bootstrap
这个部分不写代码，主要是了解和学习汇编相关知识和开机引导流程
### a.汇编
* 汇编有两种语法，一个是Intel的一个是AT&T。x86一般用Intel语法，NASM（Netwide Assembly)是使用Intel语法的汇编器，GNU使用AT&T语法
* 主要了解几种常见汇编指令   

### b.qemu的使用  
* 配置好qemu后，直接在lab下 make qemu,可以编译运行kernel  

### c. PC的物理地址空间

```

+------------------+  <- 0xFFFFFFFF (4GB)   
|      32-bit      |   
|  memory mapped   |   
|     devices      |   
|                  |   
/\/\/\/\/\/\/\/\/\/\  
  
/\/\/\/\/\/\/\/\/\/\   
|                  |   
|      Unused      |   
|                  |   
+------------------+  <- depends on amount of RAM   
|                  |   
|                  |   
| Extended Memory  |     
|                  |   
|                  |   
+------------------+  <- 0x00100000 (1MB)   
|     BIOS ROM     |   
+------------------+  <- 0x000F0000 (960KB)  
|  16-bit devices, |   
|  expansion ROMs  |   
+------------------+  <- 0x000C0000 (768KB)   
|   VGA Display    |    
+------------------+  <- 0x000A0000 (640KB)   
|                  |   
|    Low Memory    |   
|                  |   
+------------------+  <- 0x00000000 

```

* 16位的Intel 8088/86 有20位地址总线，可以寻址1MB的内存，但是由于数据总线只有16位，所以单个程序段最大只有64KB,为了可以寻址1MB，Intel引入了分段：
  * 逻辑段的开始地址必须是16的倍数，因为段寄存器长为16位；
  * 逻辑段的最大长度为64K，因为指针寄存器长为16位。 
  * 那么1M字节地址空间最多可划分成64K个逻辑段，最少也要划分成16个逻辑段。逻辑段与逻辑段可以相连，也可以不相连，还可以部分重叠。
  * 在实模式下，cpu寻址的方式是：CS:IP  物理地址是： 16*CS+IP
  * 这个博客说得很好  https://www.cnblogs.com/blacksword/archive/2012/12/27/2836216.html  
* 早期的cpu内存，只使用640KB以下的内存(被称为Low Memory)作为随机存取器（RAM），更早的使用的内存更少：16KB，32KB，64KB
* 640KB至1MB中间的384KB内存被保留作为硬件的特殊用途，比如显卡缓冲区和非易失固件内存（？）
* 被保留的最重要的区域是从0x000F0000（960KB）到0x000FFFFF（1MB）的64KB，这里会存放BIOS。BIOS会进行基本的初始化比如显卡检查和硬件检查以及内存检查
* BIOS初始化之后会从适当的位置（软盘硬盘等）加载操作系统
* 从80286和80386开始Intel支持16MB和4GB内存，但是低1MB的基本功能布局没有变化（为了兼容）
* 现代PC在640KB到1MB之间有个hole，把内存分为了低640KB的Low Memory和1MB以上的extended memory
* 并且在32位机器上，4GB的内存顶部也保留了一部分区域给32位的PCI接口设备，因此在64位机器普及后，内存又出现了第二个hole
* 这个课程的操作系统只使用低256MB内存

### d.The ROM BIOS
* 学习IA-32兼容的计算机是怎么开机的
* 打开两个终端，先后分别输入 make qemu-gdb make gdb,在输入make gdb的终端里可以使用相关gdb命令进行调试
  * si代表执行下一个语句并停下来，显示出来的是即将执行的语句，但是还未执行
* BIOS加载进内存后，将从CS=0xf00 IP=0xfff0出执行，这个语句是个jmp语句，跳到CS=0Xf000 IP=0xe05b，原因是0xffff0处于BIOS末端（因为之前的语句是把BIOS加载进来，然后就到了末尾），要执行BIOS，则要跳转到BIOS的入口出
* BIOS的功能是设置中断表、初始化设备，然后寻找一个可引导开机的设备（硬盘软盘等），然后读取开机引导设备的第一个扇区（里面的程序是bootloader）到内存0x7c00处（这个地址是随意的，但是是写死的，也就是说这个地址没什么特殊意义，只是刚好选了它，但它仍要满足一些条件，内存对齐、位置等），再跳转到bootloader的入口，控制权就转移到了bootloader  

## Part2: The Boot Loader
* 一般情况下，或者说老一代的PC其开机设备的第一个扇区存了bootloader，负责开机引导等，现代的PCbootloader会有更复杂的功能和大小
* JOS的bootloader由一个汇编文件:boot/boot.S和C源文件：boot/main.c组成，里面的内容分析：
* boot/boot.S

~~~

#include <inc/mmu.h>
# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

#.set symbol, expression 汇编意义：设置symbol为expression

.set PROT_MODE_CSEG, 0x8         # kernel code segment selector   
#段选择符的格式:13位索引+1位TI表指示标志（代表是不是全局描述符）+2位RPL
#因此 0x8  0000000000001 0 00
#此处预设代码段选择符,这个选择符代表，索引是1，TI为0表示全局描述符，RPL权限设为最高

.set PROT_MODE_DSEG, 0x10        # kernel data segment selector
#     0x10 0000000000010 0 00
#此处预设数据段选择符,代表索引是2，全局描述符，权限0最高

.set CR0_PE_ON,      0x1         # protected mode enable flag
#保护模式的设置由CR0管理，这里的标识符代表开启保护模式时CR0对应的位的值:最低位置位

.globl start  
start:                 #函数的开始，相当于main
  .code16                     # Assemble for 16-bit mode    
  #让汇编器按照16位代码汇编

  cli                         # Disable interrupts
  cld                         # String operations increment
#关闭中断，设置字符串操作是递增方向
#cld的作用是将direct flag标志位清零
#it means that instructions that autoincrement the source index and destination index (like MOVS) will increase both of them

  # Set up the important data segment registers (DS, ES, SS).

  xorw    %ax,%ax             # Segment number zero
  movw    %ax,%ds             # -> Data Segment
  movw    %ax,%es             # -> Extra Segment
  movw    %ax,%ss             # -> Stack Segment

  # Enable A20:
  #   For backwards compatibility with the earliest PCs, physical
  #   address line 20 is tied low, so that addresses higher than
  #   1MB wrap around to zero by default.  This code undoes this.

  #激活A20地址位,由于需要兼容早期pc，物理地址的第20位绑定为0，所以高于1MB的地址又回到了0x00000
  #激活A20后，就可以访问所有4G内存，就可以使用保护模式
  #激活方式：由于历史原因A20地址位由键盘控制器芯片8042管理。所以要给8042发命令激活A20
  #8042有两个IO端口：0x60和0x64,激活流程为： 先发送0xd1命令到0x64端口 --> 再发送0xdf到0x60

seta20.1:
  inb     $0x64,%al               # Wait for not busy
  #汇编语言有专门的读取端口信息的指令，in out后面的b代表一个字节

  testb   $0x2,%al
  #测试（两操作数作与运算,仅修改标志位，不回送结果）。

  jnz     seta20.1
#发送命令之前，要等待键盘输入缓冲区为空，这通过8042的状态寄存器的第2bit来观察，而状态寄存器的值可以读0x64端口得到。
#上面的指令的意思就是，如果状态寄存器的第2位为1，就跳到seta20.1符号处执行，知道第2位为0，代表缓冲区为空

  movb    $0xd1,%al               # 0xd1 -> port 0x64
  outb    %al,$0x64
#发送0xd1到0x64端口

seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.2

  movb    $0xdf,%al               # 0xdf -> port 0x60
  outb    %al,$0x60

  # Switch from real to protected mode, using a bootstrap GDT
  # and segment translation that makes virtual addresses 
  # identical to their physical addresses, so that the 
  # effective memory map does not change during the switch.
  #转入保护模式，这里需要指定一个临时的GDT，来翻译逻辑地址。
  #这里使用的GDT通过gdtdesc段定义，它翻译得到的物理地址和虚拟地址相同（段描述符里的段基址为0）
  #所以转换过程中内存映射不会改变

  lgdt    gdtdesc   
  #lgdt指令把gdtdesc的地址加载进gdtr寄存器，代表全局段描述符表

  movl    %cr0, %eax
  orl     $CR0_PE_ON, %eax
  movl    %eax, %cr0
  #开启保护模式
  # Jump to next instruction, but in 32-bit code segment.
  # Switches processor into 32-bit mode.
  #由于进入保护模式，所有地址都应该是：cs:eip

  ljmp    $PROT_MODE_CSEG, $protcseg         #ljmp cs esp
  #Long jump, use 0xfebc for the CS register and 0x12345678 for the EIP register:
  #ljmp $0xfebc, $0x12345678

  .code32                     # Assemble for 32-bit mode
protcseg:
  # Set up the protected-mode data segment registers
  movw    $PROT_MODE_DSEG, %ax    # Our data segment selector
  movw    %ax, %ds                # -> DS: Data Segment
  movw    %ax, %es                # -> ES: Extra Segment
  movw    %ax, %fs                # -> FS
  movw    %ax, %gs                # -> GS
  movw    %ax, %ss                # -> SS: Stack Segment
  
  # Set up the stack pointer and call into C.
  movl    $start, %esp
  call bootmain

  # If bootmain returns (it shouldn't), loop.
spin:
  jmp spin

# Bootstrap GDT
.p2align 2                                # force 4 byte alignment
gdt:
  SEG_NULL				# null seg
  SEG(STA_X|STA_R, 0x0, 0xffffffff)	# code seg
  SEG(STA_W, 0x0, 0xffffffff)	        # data seg

gdtdesc:
  .word   0x17                            # sizeof(gdt) - 1
  .long   gdt                             # address gdt


~~~

* boot/boot.S的功能有一个：
  * 从实模式进入32位保护模式，方法是把CR0最低位置位，即开启了保护模式，然后激活A20使得cpu可以寻址1MB以上的空间，之后设置一个段表，最后调用bootmain，进入main.c
* 



* stab的作用：
  * With the `-g` option, GCC puts in the .s' file additional debugging information, which is slightly transformed by the assembler and linker, and carried through into the nal executable. This debugging information describes features of the source file like line numbers, the types and scopes of variables, and function names, parameters, and scopes of variables, and function names, parameters, and scopes.  

   

### mit6.828-lab2:memory management  
#### Introduce  
这次实验，我们要为我们的操作系统写一个内存管理器。   

内存管理器有两个组成部分：
1. 第一个组成部分是内核的物理内存分配器，可以让内核分配内存以及释放内存。我们写的这个分配器，以4K为一个操作单元（称作一个页）。我们的任务是管理记录物理内存状态的一个数据结构（引用数、下一个页地址等）。我们还会写一系列与分配和释放物理内存相关的函数。
2. 第二个组成部分是虚拟内存管理组件，它将内核和用户使用的虚拟内存映射到物理内存中。x86的内存管理单元硬件将完成虚拟地址向物理地址的映射，通过一些页表。我们将根据提供的一个特殊布局来修改JOS，从而建立一个内存管理单元的页表系统。  
<!--more-->



---
title: mit6.828-lab3
top: false
cover: false
toc: true
mathjax: true
date: 2020-12-02 23:40:02
password:
summary:
tags: [OS]
categories:
---
## mit6.828-lab3:user environments
在这个lab里你将:
* 完成基本的用户进程相关设施和数据结构(envs struct等). 
* 加载一个程序镜像到内存并运行它.
* 完成中断/异常,系统调用的相关设施,让kernel有能力处理中断/异常和系统调用.  
<!-- more -->
### partA:user environments and exception handling
首先是用户相关的数据结构`Env`:
```c
struct Env {
	struct Trapframe env_tf;	// Saved registers
	struct Env *env_link;		// Next free Env
	envid_t env_id;			// Unique environment identifier
	envid_t env_parent_id;		// env_id of this env's parent
	enum EnvType env_type;		// Indicates special system environments
	unsigned env_status;		// Status of the environment
	uint32_t env_runs;		// Number of times environment has run
	// Address space
	pde_t *env_pgdir;		// Kernel virtual address of page dir
};   
```
<!--more-->      
进程上下文切换的相关结构:   
```c
struct PushRegs {
	/* registers as pushed by pusha */
	uint32_t reg_edi;
	uint32_t reg_esi;
	uint32_t reg_ebp;
	uint32_t reg_oesp;		/* Useless */
	uint32_t reg_ebx;
	uint32_t reg_edx;
	uint32_t reg_ecx;
	uint32_t reg_eax;
} __attribute__((packed));
struct Trapframe {
	struct PushRegs tf_regs;
	uint16_t tf_es;
	uint16_t tf_padding1;
	uint16_t tf_ds;
	uint16_t tf_padding2;
	uint32_t tf_trapno;
	/* below here defined by x86 hardware */
	uint32_t tf_err;
	uintptr_t tf_eip;
	uint16_t tf_cs;
	uint16_t tf_padding3;
	uint32_t tf_eflags;
	/* below here only when crossing rings, such as from user to kernel */
	uintptr_t tf_esp;
	uint16_t tf_ss;
	uint16_t tf_padding4;
} __attribute__((packed));

```
```c
void
env_pop_tf(struct Trapframe *tf)
{
	asm volatile(
		"\tmovl %0,%%esp\n"
		"\tpopal\n"
		"\tpopl %%es\n"
		"\tpopl %%ds\n"
		"\taddl $0x8,%%esp\n" /* skip tf_trapno and tf_errcode */
		"\tiret\n"
		: : "g" (tf) : "memory");
	panic("iret failed");  /* mostly to placate the compiler */
}

```
`%0`表示`tf`代表的寄存器,`movl %0,%%esp`把`tf`的地址存入`esp`寄存器中,`popal`是`popa`的长指令(pop all).  
`pusha`作用是:把八个通用寄存器全部`push`入`esp`中,顺序为`eax ecx edx ebx oldesp ebp esi edi`而`popa`的作用相反:从`esp`中把这八个值弹出到相应的寄存器,但是并不弹出`old_esp`,会跳过它,方式是`esp`+4.   
IRET是一个汇编指令,这个指令会做很多事情:   
the IRET instruction pops the return instruction pointer, return code segment selector, and EFLAGS image from the stack to the EIP, CS, and EFLAGS registers, respectively, and then resumes execution of the interrupted program or procedure. If the return is to another privilege level, the IRET instruction also pops the stack pointer and SS from the stack, before resuming program execution.  

```

Operation
IF OperandSize = 32 (* instruction = POPAD *)
THEN
EDI ← Pop();
ESI ← Pop();
EBP ← Pop();
increment ESP by 4 (* skip next 4 bytes of stack *)
EBX ← Pop();
EDX ← Pop();
ECX ← Pop();
EAX ← Pop();
ELSE (* OperandSize = 16, instruction = POPA *)
DI ← Pop();
SI ← Pop();
BP ← Pop();
increment ESP by 2 (* skip next 2 bytes of stack *)
BX ← Pop();
DX ← Pop();
CX ← Pop();
AX ← Pop();
参考资料:https://www.cs.cmu.edu/~410/doc/intel-isr.pdf
```
参考:https://www.cnblogs.com/whutzhou/articles/2638498.html  
`env_pop_tf()`的作用是:转到`tf`代表的用户程序,先把`esp`设为这个`Trapframe`的地址,然后`popa`,即从`tf`中的`struct PushRegs tf_regs`弹出值到相应的寄存器,实现上下文的切换.然后再从`tf`中弹出`es`和`ds`的值,再跳过`tf_trapno and tf_errcode`,最后`iret`.    
值得注意的是:栈是从上往下增长的,`tf`陷阱门是从下网上长的,因此把`esp`设为`tf`,`pop`弹出值的时候,`esp`回退(即往上),对应着`tf`往上依次读取成员.

#### exercise2
完成几个函数:
* `env_init()`:初始化所有的在`envs`数组中的`Enc`结构体,并把他们添加到`env_free_list`指针后面,之后调用`env_init_per_cpu`以设置段管理的相关硬件,它们分别是特权级0(kernel)和特权级3(user)的段.
* `env_setup_vm()`:为新的`environment`分配一个页目录表,并且初始化新的地址空间中的内核部分(通过复制).
* `region_alloc()`:为新的`environment`分配并映射物理地址.
* `load_icode()`:需要自己实现解析ELF二进制文件的功能(就和`bootloader`里面做的一样),并把二进制文件的内容加载到新的`environment`的用户地址空间中.
* `env_create`:通过`env_alloc()`分配一个`environment`,并且调用`load_icode()`把ELF二进制文件加载进去.
* `env_run`:在用户模式下启动一个给定的`environment`.
代码解析:  
* `env_init()`:  

```c

// Mark all environments in 'envs' as free, set their env_ids to 0,
// and insert them into the env_free_list.
// Make sure the environments are in the free list in the same order
// they are in the envs array (i.e., so that the first call to
// env_alloc() returns envs[0]).
//
void
env_init(void)
{
	// Set up envs array
	// LAB 3: Your code here.
	size_t i = 0;
	env_free_list = envs;
    //让env_free_list等于数组第一个元素,再让整个数组通过链表连起来
    //env_link指向下一个节点,同时把id设置为0
    //让最后一个节点指向null
	for (i = 0; i < NENV-1; i++)
	{
		envs[i].env_link = envs + i + 1;
		envs[i].id = 0;

	}
	(envs + NENV - 1)->env_link = NULL;
	// Per-CPU part of the initialization
	env_init_percpu();
}

```

* env_setup_vm():

```c

// Initialize the kernel virtual memory layout for environment e.
// Allocate a page directory, set e->env_pgdir accordingly,
// and initialize the kernel portion of the new environment's address space.
// Do NOT (yet) map anything into the user portion
// of the environment's virtual address space.
//
// Returns 0 on success, < 0 on error.  Errors include:
//	-E_NO_MEM if page directory or table could not be allocated.
//
static int
env_setup_vm(struct Env *e)
{
	int i;
	struct PageInfo *p = NULL;

	// Allocate a page for the page directory
	if (!(p = page_alloc(ALLOC_ZERO)))
		return -E_NO_MEM;

	// Now, set e->env_pgdir and initialize the page directory.
	//
	// Hint:
	//    - The VA space of all envs is identical above UTOP
	//	(except at UVPT, which we've set below).
	//	See inc/memlayout.h for permissions and layout.
	//	Can you use kern_pgdir as a template?  Hint: Yes.
	//	(Make sure you got the permissions right in Lab 2.)
	//    - The initial VA below UTOP is empty.
	//    - You do not need to make any more calls to page_alloc.
	//    - Note: In general, pp_ref is not maintained for
	//	physical pages mapped only above UTOP, but env_pgdir
	//	is an exception -- you need to increment env_pgdir's
	//	pp_ref for env_free to work correctly.
	//    - The functions in kern/pmap.h are handy.

	// LAB 3: Your code here.

	e->env_pgdir =(pde_t*) page2kva(p);
	memcpy(e->env_pgdir, kern_pgdir, PGSIZE);
	p->pp_ref++;
	// UVPT maps the env's own page table read-only.
	// Permissions: kernel R, user R
	e->env_pgdir[PDX(UVPT)] = PADDR(e->env_pgdir) | PTE_P | PTE_U;

	return 0;
}


```

* `region_alloc`:
为进程分配`len`个字节的物理内存并且映射到`va`所代表的虚拟地址上,不要设置0或者初始化被映射的页(page_alloc()传0进去就可以).   
页面的权限应该是用户和内核都可写的.  
如果分配失败则`panic`  

```c

//
// Allocate len bytes of physical memory for environment env,
// and map it at virtual address va in the environment's address space.
// Does not zero or otherwise initialize the mapped pages in any way.
// Pages should be writable by user and kernel.
// Panic if any allocation attempt fails.
//
static void
region_alloc(struct Env *e, void *va, size_t len)
{
	// LAB 3: Your code here.
	// (But only if you need it for load_icode.)
	//
	// Hint: It is easier to use region_alloc if the caller can pass
	//   'va' and 'len' values that are not page-aligned.
	//   You should round va down, and round (va + len) up.
	//   (Watch out for corner-cases!)
	void *low = ROUNDDOWN(va, PGSIZE);//向下取整,即把va所在的那一页全部映射,从va前面页面对齐开始
	void *up = ROUNDUO(va + len, PGSIZE);//向上取整
	for (; low < up;low+=PGSIZE)
	{
		struct PageInfo *p = page_alloc(0);
		if(!p)
		{
			panic("region_alloc error: region_alloc failed!\n");
		}
		p->pp_ref++;
		page_insert(e->env_pgdir, p, low, PTE_W|PTE_U);
	}
}

```

* `load_icode`:
为用户进程设置初始的二进制程序,栈,处理器标志等.  
这个函数只在内核初始化的时候被调用,在运行第一个用户态进程之前.  
这个函数从二进制镜像加载所有可加载的段到进程的内存中,从适当的、二进制文件头里描述的虚拟地址开始.   
同时它把在二进制头里要求的一些段的内容设置为0,比如`bss segment`.  
这些和我们的`boot loader`所做的很像,但是它是从硬盘读取代码.去参考下`boot/main.c`里的代码.  
最后,这个函数从这个进程的初始栈映射一个页.  
如果它遇到任何问题,则会`panic`,请思考它在什么情况下会出错.

#### the task state segment
处理器需要一个地方储存中断或者异常发生之前的处理器状态,比如`EIP`和`CS`的值,以便当异常或者中断执行完毕后可以恢复cpu的状态,并从原来的程序位置重新执行.  
但是这个储存的地方,也必须免受权限不够的用户态程序影响,否则一些恶意程序会影响kernel.  
因此x86处理器当特权级切换的时候也会切换栈,`TSS`任务状态段的目的便是服务这一过程,它指定了段选择符并指出这个栈在段中的位置,处理器会`push` `SS,ESP,EFLAGS,CS,EIP`和error code到这个栈里(error code只有某些中断或者异常会有,有的没有).随后处理器从中断描述符中加载`CS`和`EIP`以切换到新栈.  
在JOS的实现中,当处理器从中断描述符中加载`CS`和`EIP`后,接下来的指令开始压入error code(如果cpu之前没有压的话),trap编号,然后`call _alltraps`,压入`ds es`然后`pushal`等等,目的是在kernel的栈上构造一个`Trapframe`,它保存了中断前进程的状态,在`trap()`中会复制这个结构体到`curenv->env_tf`中,以便之后恢复现场.
以上的意思是:当转移控制权时,如果特权级发生变化,那么先要把当前处理器状态存入一个安全的`TSS`指定的栈中,再切换到目的栈,这个过程涉及到三个栈:当前栈,`TSS`指定的栈和将要转移到的代码段的栈.    

```
http://blog.chinaunix.net/uid-685034-id-2076045.html  
堆栈切换和任务切换
堆栈切换
中断发生时,从用户堆栈切换到内核堆栈是硬件完成的是吗？需要软件上哪些支持呢？
x86处理器是由硬件完成的.
但很多RISC(reduced instruction set computer,精简指令集计算机,例如：MIPS R3000、HP—PA8000系列,Motorola M88000等均属于RISC微处理器)处理器必须由软件来实现用户态与核态之间的堆栈切换
X86是CISC处理器(复杂指令集计算机(Complex Instruction Set Computer,CISC))
X86处理器的SP切换过程是这样的：

当中断或异常发生时,处理器会检查是否有CPU运行级别的改变,如果有的话,则进行堆栈切换.切换的过程如下：

1. 读取TR寄存器以便访问当前进程的TSS段,因为TSS段中保存着当前进程在核心态下的堆栈指针.
2. 从TSS段中加载相应的堆栈地址到SS和ESP寄存器中.
3. 在核态堆栈中,保存用户态下的SS寄存器和ESP寄存器值.

由于linux内核仅使用了一个TSS段,因此当发生进程切换时,内核必须将新进程的核态堆栈更新到TSS段中.

而对于RISC处理器而言, 本着“简洁”的设计原则,当发生中断或异常时,CPU仅仅只是跳转到某个TRAP向量地址去执行(当然,硬件还是会自动设置处理器状态寄存器PSR中的核心态标志位,同时保存trap发生前的处理器运行级别),而其余的工作就都统统留给软件去完成了.

因此,RISC处理器的trap handler通常都做这样的一些工作：

1.根据trap发生前的处理器运行级别判断是否需要进行堆栈切换. 如果trap发生之前就是处在核心态下,那显然就不要切换堆栈.而是直接去做SAVE_ALL好了.

2. 如果之前是用户态,那么从内核的某个固定的地址加载当前进程的核态SP指针.然后进行SAVE_ALL保存中断现场.
#####
我们知道每个进程都有一个用户堆栈与系统堆栈,那么此外是否还有一个操作系统内核专用的堆栈呢？
BTW：内核代码都是运行在当前进程的核心态堆栈中的,并不需要专门的堆栈
########
那么当系统初始化时,系统中第一个进程还没有生成的时候,用的是哪个堆栈呢？
从head.s程序起,系统开始正式在保护模式下运行.此时堆栈段被设置为内核数据段(0x10),堆栈指针esp设置成指向user_stack数组的顶端,保留了1页内存(4K)最为堆栈使用.此时该堆栈是内核程序自己使用的堆栈.
(有疑问的答案：系统初始化用的是0进程的堆栈 －－ 也就是是init_task的堆栈.
整个start_kernel()都是在init_task的堆栈中执行的.start_kernel()最后clone出1进程－－也就是init进程.然后0进程就去执行cpu_idle()函数了－－也就是变成idle进程了.然后发生一次进程调度(进程切换时会切换内核堆栈),init进程得到运行,此时内核就在init进程的堆栈中运行.)
#####
任务0的堆栈
    任务0的堆栈比较特殊,在执行了move_to_user_mode()之后,它的内核堆栈位于其任务数据结构所在页面的末端,而它的用户态堆栈就是前面进入保护模式后所使用的堆栈,即user_stack数组的位置.任务0的内核态堆栈是在其人工设置的初始化任务数据结构中指定的,而它的用户态堆栈是在执行move_to_user_mode()时,在模拟iret返回之前的堆栈中设置的.在该堆栈中,esp仍然是user_stack中原来的位置,而ss被设置成0x17,也即用户局部表中的数据段,也即从内存地址0开始并且限长640KB的段.
 
任务切换
I386硬件任务切换机制
 
1.I386硬件任务切换机制
　　 Intel 在i386体系的设计中考虑到了进程的管理和调度,并从硬件上支持任务间的切换.为此目的,Intel在i386系统结构中增设了一种新的段“任务状态段”TSS.一个TSS虽然说像代码段,数据段等一样,也是一个段,实际上却是一个104字节的数据结构,用以记录一个任务的关键性的状态信息.
　　 像其他段一样,TSS也要在段描述表中有个表项.不过TSS只能在GDT中,而不能放在任何一个LDT中或IDT中.若通过一个段选择项访问一个TSS,而选择项中的TI位为1,就会产生一次GP异常.
　　 另外,CPU中还增设一个任务寄存器TR,指向当前任务的TSS.相应地,还增加了一条指令LTR,对TR寄存器进行装入操作.像CS和DS一样,TR也有一个程序不可见部分,每当将一个段选择码装入到TR中时,CPU就会自动找到所选择的TSS描述项并将其装入到TR的程序不可见部分,以加速以后对该TSS段的访问.
　　 还有,在IDT表中,除了中断门、陷阱门和调用门以为,还定义了一种任务门.任务门中包含一个TSS段选择码.当CPU因中断而穿过一个任务门时,就会将任务门中的选择码自动装入TR,使TR指向新的TSS,并完成任务的切换.CPU还可以通过JMP和CALL指令实现任务切换,当跳转或调用的目标段实际上指向GDT表中的一个TSS描述项时,就会引起一次任务切换.


```

```
内核栈的实现
以linux内核为例,内核在创建进程并时,首先需要给进程分配task_struct结构体,在做这一步的时候内核实际上分配了两块连续的物理空间(一般是1个物理页),上边供堆栈使用,下边保存进程描述符task_struct.这个整体叫做进程的内核栈,因此task_struct是在进程内核栈内部的.
当为内核栈分配地址空间的时候,分配一个页面(这里以8k为例)返回的地址是该该页面的低地址,而栈是由高地址向低地址增长的,栈顶指针只需将该内核栈的首地址+8k即可

```

#### nested exceptions and interrupt
在用户态和内核态处理器都可以接受异常和中断,但是x86只有从用户态切换到内核态的时候才会在储存cpu当前状态时自动切换栈(其他时候不会),然后再从中断向量表中invoke适当的中断或异常.  
如果处理器以及处于内核态了(即`CS`的低2位为0),那么处理器只是把当前处理器状态再次储存到当前栈中而不切换栈.下面在`system call`中我们可以看到这个特性的好处.
如果处理器已经在内核态了,并出发了嵌套异常,由于它不用切换栈,因此`SS`和`ESP`寄存器的状态就没有必要储存了,因此只需储存 `EFLAGS,CS,EIP`和error code,如果内核栈已经满了,这个时候再次出现中断或者异常, `EFLAGS,CS,EIP`压不进去了,就会出现不能恢复原来现场的功能,这是一个bug,处理器面对这样的情况时,粗暴地重置自己,设计kernel的时候应该避免这种情况.  

There are two sources for external interrupts and two sources for
exceptions:
 1. Interrupts
 * Maskable interrupts, which are signalled via the INTR pin.
 * Nonmaskable interrupts, which are signalled via the NMI
 (Non-Maskable Interrupt) pin.
 2. Exceptions
 * Processor detected. These are further classified as faults, traps,
 and aborts.
 * Programmed. The instructions INTO, INT 3, INT n, and BOUND can
 trigger exceptions. These instructions are often called "software
 interrupts", but the processor handles them as exceptions.   
INTR是一个外部中断请求触发器,这个触发器可以传递中断,INTR为“1”时(即有设备请求中断),表示该设备向CPU提出中断请求.但是设备如果要提出中断请求,其设备本身必须准备就绪,即接口内的完成触发器D的状态必须为“1”.MASK为中断屏蔽触发器,如果是“1”,中断会被屏蔽掉,封锁中断源的请求.仅当设备准备就绪(D=1),且该设备未被屏蔽(MASK=0)时,CPU的中断查询信号可将中断请求触发器置“1”.
NMI是2号中断,它由cpu直接使用,操作系统不能使用,它用来处理一些严重的突发情况比如电源掉电、存储器读写出错、总线奇偶位出错等.NMI线上中断请求是不可屏蔽的(即无法禁止的)、而且立即被CPU锁存.因此NMI是边沿触发,不需要电平触发.NMI的优先级也比INTR高.不可屏蔽中断的类型指定为2,在CPU响应NMI时,不必由中断源提供中断类型码,因此NMI响应也不需要执行总线周期INTA.   


#### setting up the idt
下面我们将设置idt去处理0-31的异常和中断,system call和32-47的中断和异常会在以后的lab实现.  
`inc/trap.h`和`kern/trap.h`中有中断和异常的相关定义,`kern/trap.h`中定义的只用在kernel里,`inc/trap.h`中定义的在用户程序中也会起作用.  
note:0-31中有intel保留的项,这些项随便自己怎么处理.  
每个异常或者中断都应该在`trapentry.S`中有它自己的handler,并且`trap_init()`应该用这些handler的地址初始化IDT.每个handler应该在栈上建立一个`struct Trapframe`并且通过一个指向Trapframe的地址call`trap()`.然后`trap()`会处理异常/中断,或者交给另一个处理函数处理.  
#### exercise 4
任务:编辑`trapentr.S`和`trap.c`并且实现上述描述的功能,`TRAPHANDLER`和`TRAPHANDLER_NOEC`宏可以帮到你,`T_*`也可以.你需要在`trapentry.S`为每一个`trap`添加entry point,你需要提供`TRAPHANDLER`指向的`_alltrap`函数,你也要修改`trap_init()`去初始化idt使得它指向每个entry point,`SETGAE`宏会帮到你.  
* `_alltrap`应该:
  * push values 以让栈看起来像一个`struct Trapframe`
  * 把`GD_KD`(kernel data段)加载进`%ds`和`%es`中 (怎么加载?我一开始用的`movl $GD_KD %ds`,但是报错了,原因是段寄存器不能通过立即数赋值,只能通过通用寄存器或存储器赋值,因此使用`pushl $GD_KD popl %ds)
  * `pushl %esp`把地址传给`Trapframe`将作为一个`trap()`的一个参数
  * call `trap()` trap可以返回吗?//不可以


```c
/* See COPYRIGHT for copyright information. */

#include <inc/mmu.h>
#include <inc/memlayout.h>
#include <inc/trap.h>



###################################################################
# exceptions/interrupts
###################################################################

/* TRAPHANDLER defines a globally-visible function for handling a trap.  TRAPHANDLER为处理中断/异常定义了一个全局可见的函数
 * It pushes a trap number onto the stack, then jumps to _alltraps.		这个函数把trap number压栈然后跳转到 _alltraps函数
 * Use TRAPHANDLER for traps where the CPU automatically pushes an error code.	TRAPHANDLER用在处理器自动压栈错误码的中断/异常中(即有错误码的中断/异常,没有错误码的用下面的TRAPHANDLER_NOEC函数处理)
 *
 * You shouldn't call a TRAPHANDLER function from C, but you may	不能够在c语言程序中调用TRAPHANDLER
 * need to _declare_ one in C (for instance, to get a function pointer	但是需要在c语言程序中声明TRAPHANDLER定义的函数
 * during IDT setup).  You can declare the function with	以便于在建立idt的时候获得相应函数指针
 *   void NAME();											声明方式是: void name();
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

/*
 * Lab 3: Your code here for _alltraps
 */
//根据Trapframe结构可以看出,处理器已经把SS,ESP,EFLAGS,CS,EIP压栈了
//上面的函数又把error code和trap number压栈了
//剩下只有ds es还有pusha对应的没有压了
//再根据实验提示,把GD_KD加载进ds和es最后call trap
_alltraps:
	pushl %ds
	pushl %es
	pushal 
	movl $GD_KD %ds
	movl $GD_KD %es
	pushl %esp
	call trap

```
##### the breakpoint exception
断点异常被用来允许debugger在一个程序中插入断点,方式是临时把程序中的某个位置的代码用`int3`代替,`int3`是一个一字节的汇编代码,因此可以放入几乎所有地方.因此当程序执行到这个地方的时候,就会发生中断,进而运行相应的中断程序,这个时候往往可以看到程序的上下文内容,以此来调试代码.  
JOS把3号中断向量的处理程序设为`monitor()`,因此发生断点异常的时候,将会进入`monitor()`程序.
Questions  
4. The break point test case will either generate a break point exception or a general protection fault depending on how you initialized the break point entry in the IDT (i.e., your call to SETGATE from trap_init). Why? How do you need to set it up in order to get the breakpoint exception to work as specified above and what incorrect setup would cause it to trigger a general protection fault?   
break point 的dpl应该设为3,因为用户态程序也会用到.否则会因为权限不够而产生一般保护性异常.
5. What do you think is the point of these mechanisms, particularly in light of what the user/softint test program does?   




##### system call
c
对于用户程序来说,执行`cprintf()`等函数需要调用系统调用.  
比如一个用户程序执行`cprintf()`,这是`lib/printf.c`下的函数,是一个普通函数,但是这个函数需要IO输出,就涉及到kernel的资源调度,因此需要通过系统调用完成,它最终会调用`sys_cputs()`,这个函数又会调用`lib/syscall.c`中的`syscall()`,这个函数先通过汇编将函数参数压入通用寄存器,通过这个方式传递参数给即将产生的`int 0x30`中断.  

```
static inline int32_t
syscall(int num, int check, uint32_t a1, uint32_t a2, uint32_t a3, uint32_t a4, uint32_t a5)
{
	int32_t ret;

	// Generic system call: pass system call number in AX,
	// up to five parameters in DX, CX, BX, DI, SI.
	// Interrupt kernel with T_SYSCALL.
	//
	// The "volatile" tells the assembler not to optimize
	// this instruction away just because we don't use the
	// return value.
	//c
	// The last clause tells the assembler that this can
	// potentially change the condition codes and arbitrary
	// memory locations.

	asm volatile("int %1\n"
		     : "=a" (ret)
		     : "i" (T_SYSCALL),
		       "a" (num),
		       "d" (a1),
		       "c" (a2),
		       "b" (a3),
		       "D" (a4),
		       "S" (a5)
		     : "cc", "memory");

	if(check && ret > 0)
		panic("syscall %d returned %d (> 0)", num, ret);

	return ret;
}


```

之后交给中断处理程序来处理相应的函数.这里会通过`trap_dispatch()`传递给`kern/syscall.c`中的`syscall()`,该函数根据系统调用调用号调用`kern/print.c`中的`cprintf()`函数,该函数最终调用`kern/console.c`中的`cputchar()`将字符串打印到控制台.当`trap_dispatch()`返回后,`trap()`会调用`env_run(curenv)`;,该函数会将`curenv->env_tf`结构中保存的寄存器快照重新恢复到寄存器中,这样又会回到用户程序系统调用之后的那条指令运行,只是这时候已经执行了系统调用并且寄存器`eax`中保存着系统调用的返回值.任务完成重新回到用户模式CPL=3.  
对比一下普通的函数调用和中断以及系统调用参数传递的区别:
* 普通函数掉用,如果没有特权级的变化,堆栈不会改变,函数调用过程是:
  * 先从右往左先把参数入栈,然后跳转到被调函数的地址
  * 被调函数开始:把ebp压栈(先esp-1,然后把ebp的值存入esp),然后把esp的值赋给ebp.被调用函数通过esp+x(即往回找)来获得参数.  
  * 最后函数会把返回值存入eax寄存器,主调函数通过eax寄存器获得返回值.  
* 中断是先保存所有寄存器的值然后调用其他函数,返回的时候恢复现场,对程序运行没有影响.
* 系统调用先调用普通函数,然后把参数压入eax等通用寄存器来传递参数.中断完成之后返回现场,但会把返回值通过`tf->tf_regs.reg_eax=syscall()`写入eax中,被调用的普通函数把ret写入eax返回给主调函数.    
* 可变参数:



##### 
中断和异常一般是在程序运行过程中发生的,这个时候cpu执行 INT n指令,





#### 杂
bootstack在哪里?   
kernel的初始化代码`entry.S`里,由编译器分配  
并且本质上esp的位置决定了栈的位置,因此只需要把esp置为想要的栈的位置就行了,栈的增长方式和具体细节由编译器提前决定(即设好规则,当什么时候,增长多少)

```
mov	$relocated, %eax
	jmp	*%eax
relocated:

	# Clear the frame pointer register (EBP)
	# so that once we get into debugging C code,
	# stack backtraces will be terminated properly.
	movl	$0x0,%ebp			# nuke frame pointer

	# Set the stack pointer
	#这个位置设置的内核用栈,因为esp决定了栈的位置
	movl	$(bootstacktop),%esp

	# now to C code
	call	i386_init


```

```

.data
###################################################################
# boot stack
###################################################################
	.p2align	PGSHIFT		# force page alignment
	.globl		bootstack
bootstack:
	.space		KSTKSIZE //32K
	.globl		bootstacktop   
bootstacktop:

```
用户进程怎么使用用户栈?  
kernel通过把用户进程的`Trapframe`的`tf_esp`设为`USTKTOP`就行了,而这个栈的物理页会有内核特别申请,映射.  
用户的内核栈由tf_esp0指定,在JOS中,大家共享一个内核栈,或者说这是不一定的,但是具体实现的时候是指向相同的地方,每个CPU有单独的内核栈.  


```

//通过这一步把用户栈设为USTACKTOP,之后esp就在这个位置往下增长
	//由此可以看出,esp决定了栈的位置
	e->env_tf.tf_esp = USTACKTOP;
	e->env_tf.tf_cs = GD_UT | 3;
	// You will set e->env_tf.tf_eip later.

```

在用户进程中,用户是怎么得到`envs`的地址的?(因为envs是定义在kernel里的,用户不能访问,而kernel把这个地方映射给了`UENVS`,用户只能访问这个`UENVS`里的envs,是怎么访问的呢?)  
在用户的`entry.S`文件里,有这样一段:  

```

.data
// Define the global symbols 'envs', 'pages', 'uvpt', and 'uvpd'
// so that they can be used in C as if they were ordinary global arrays.
	.globl envs
	.set envs, UENVS  //这个地方把envs的值设为UENVS,从此,用户进程访问envs就指向UENVS,而不是kernel里原来的envs,下面同理
	.globl pages
	.set pages, UPAGES
	.globl uvpt
	.set uvpt, UVPT
	.globl uvpd
	.set uvpd, (UVPT+(UVPT>>12)*4)

```
日志:`make qemu |tee -a linux.log`   
* 类似于将水流发送到两个方向的三通管,`tee`命令将输出发送到终端以及文件(或作为另一个命令的输入).你可以像这样使用它:`command | tee file.txt`如果该文件不存在,它将自动创建.还可以使用 tee 命令 -a 选项进入附加模式.    
* 管道是一种通信机制,通常用于进程间的通信(也可通过socket进行网络通信),它表现出来的形式将前面每一个进程的输出(stdout)直接作为下一个进程的输入(stdin)
`trap()`中incoming Trapframe的地址:  
此时,这个是内核栈中的Trapframe,因此是内核栈中的地址:0xefffffbc 内核栈顶是:0xf0000000 相差4+4*16=68= sizeof(struct Trapframe)    
如果用户的内核栈和内核用的栈相同,而用户的内核栈每次使用时都默认里面没有内容,从栈底开始,那么就破坏了内核的内容,该怎么办?  
这个时候已经返回内核了,在JOS中,会继续在内核栈中执行,知道最后销毁进程,销毁之后进入`monitor()`,实际上这对内核没有什么影响,因为进入了monitor,但是之后不知道会不会有影响,我猜应该把内核用的栈和内核栈分开,当程序销毁后,再切换到内核用的栈.  
进程从用户态进入内核态的三种方式:
* 异常
* 外围设备中断
* 系统调用
系统调用的三种实现方法:   

---
title: mit6.828 lab4
top: false
cover: false
toc: true
mathjax: true
date: 2020-12-20 05:02:19
password:
summary:
tags:
categories:
---

# Introduce
这个实验将完成多处理器中的进程调度.  
在partA中将:
* 给JOS添加多处理器的支持
* 完成轮询调度
* 添加基本的进程管理系统调用(产生和销毁新进程,分配和映射内存)
在partB中:
* 实现一个和unix类似的`fork()`函数以允许用户进程产生一个自己的拷贝
在partC中:
* 实现进程间通讯以允许不同的用户进程进行交流和同步
* 实现时钟中断和优先权
<!-- more -->

# PartA: multiprocessor support and cooperative multitasking
* 让系统可以跑在多处理器环境中
* 实现一个新的系统调用以允许用户进程创建新进程
* 实现协作轮询调度以允许用户进程可以资源放弃cpu,让内核切换进程

## multiprocessor support
让JOS支持symmetric multiprocessor(SMP,对称多处理器,即地位相同).  


**excercise 1**
参照`boot_map_region()`就行,值得注意的是`pa`和`size`分别都要取整,`pa`想下取整,即从`pa`开始的那个页首开始映射,`size`向上取整,即每次映射`PGSIZE`整数倍的大小.   
而返回值根据调用它的函数
```
// lapicaddr is the physical address of the LAPIC's 4K MMIO
	// region.  Map it in to virtual memory so we can access it.
	lapic = mmio_map_region(lapicaddr, 4096);
```
可以看出,返回的是映射的首地址.  
```
//
// Reserve size bytes in the MMIO region and map [pa,pa+size) at this
// location.  Return the base of the reserved region.  size does *not*
// have to be multiple of PGSIZE.
//
void *
mmio_map_region(physaddr_t pa, size_t size)
{
	// Where to start the next region.  Initially, this is the
	// beginning of the MMIO region.  Because this is static, its
	// value will be preserved between calls to mmio_map_region
	// (just like nextfree in boot_alloc).
	static uintptr_t base = MMIOBASE;

	// Reserve size bytes of virtual memory starting at base and
	// map physical pages [pa,pa+size) to virtual addresses
	// [base,base+size).  Since this is device memory and not
	// regular DRAM, you'll have to tell the CPU that it isn't
	// safe to cache access to this memory.  Luckily, the page
	// tables provide bits for this purpose; simply create the
	// mapping with PTE_PCD|PTE_PWT (cache-disable and
	// write-through) in addition to PTE_W.  (If you're interested
	// in more details on this, see section 10.5 of IA32 volume
	// 3A.)
	//
	// Be sure to round size up to a multiple of PGSIZE and to
	// handle if this reservation would overflow MMIOLIM (it's
	// okay to simply panic if this happens).
	//
	// Hint: The staff solution uses boot_map_region.
	//
	// Your code here:
	size = ROUNDUP(size, PGSIZE);
	pa = ROUNDDOWN(pa, PGSIZE);
	if (base + size >= MMIOLIM)
	{
		panic("mmio_map_region overflow MMIOLIM!\n");
	}
	boot_map_region(kern_pgdir, base, size, pa, PTE_PCD | PTE_PWT | PTE_W);
	base += size;
	//panic("mmio_map_region not implemented");
	//返回此次映射的base
	return (void *)(base - size);
}
```
**exercise 2**   
在`page_init()`里面再加个条件就行.   
```
	if (i == 0 || i == (MPENTRY_PADDR / PGSIZE)) 
		{
			pages[i].pp_ref = 1;
			pages[i].pp_link = NULL;
		}
```

```
Question 

1.Compare kern/mpentry.S side by side with boot/boot.S. Bearing in mind that kern/mpentry.S is compiled and linked to run above KERNBASE just like everything else in the kernel, what is the purpose of macro MPBOOTPHYS? Why is it necessary in kern/mpentry.S but not in boot/boot.S? In other words, what could go wrong if it were omitted in kern/mpentry.S?
Hint: recall the differences between the link address and the load address that we have discussed in Lab 1.
```
答:因为对于`boot/boot.S`来说,它是运行在实模式下的,对它的寻址就是对实模式下物理地址中的寻址,因此它的寻址是对的.而对于`kern/mpentry.S`来说,这个文件的二进制代码也是和其他文件一起加载进物理内存的,并且`kern/mpentry.S`运行时,BSP开启了分页,且有了页表,此时对`kern/mpentry.S`文件里的对象寻址,得到的是`KERNBASE`上面的一个虚拟地址,而它实际上是被加载进0x7000的,如果按照原来的linker设置的地址寻址,会出问题.

## Locking
现在我们的代码会在`mp_main()`里初始化AP后自旋/无限循环(一个for循环).在进行下一步之前,我们需要强调一下当多处理器同时运行内核代码时的竞争条件(race conditions).实现这个的最简单方式是用一个大内核锁.大内核锁是一个单独的全局锁,当有进程进入内核态时就拥有这把锁,然后在返回用户态时释放锁.在这个模型中,在用户态的进程能在多cpu上并发,但是只有一个进程能运行在内核态;任何其他想要进入内核态的进程将被强制阻塞(等待). 
这个锁使得同时只有一个cpu处于内核态,而其他cpu想要进入内核态只能等待其他cpu退出内核态.
问题:为什么只能允许一个进程进入内核态?    
如果同时有多个cpu处于内核态,它们可能会修改相关的数据和数据结构,使得cpu之间出现混乱.  
`kern/spinlock.h`声明了一个大内核锁:`extern struct spinlock kernel_lock;`   
定义在`kern/spinlock.c`:
```
// The big kernel lock
struct spinlock kernel_lock = {
#ifdef DEBUG_SPINLOCK
	.name = "kernel_lock"
#endif
};
```
这个锁的结构:
```
// Mutual exclusion lock.
//互斥锁
struct spinlock {
    //如果锁被获取,locked=1,反之lock=0
	unsigned locked;       // Is the lock held?
    //为了debug时能发现是谁拥有锁
#ifdef DEBUG_SPINLOCK
	// For debugging:
	char *name;            // Name of lock.
	struct CpuInfo *cpu;   // The CPU holding the lock.
	uintptr_t pcs[10];     // The call stack (an array of program counters)
	                       // that locked the lock.
#endif
};
```
并且提供了`lock_kernel()`和`unlock_kernel()`函数来获取和释放锁.    
对于锁的实现需要用到一些原子指令,一个不用原子指令的获取锁的实现是:
Logically, xv6 should acquire a lock by executing code like
```
21 void
22 acquire(struct spinlock *lk)
23 {
24 for(;;) {
25 if(!lk->locked) {
26 lk->locked = 1;
27 break;
28 }
29 }
30 }
```
>Unfortunately, this implementation does not guarantee mutual exclusion on a multiprocessor. It could happen that two CPUs simultaneously reach line 25, see that lk->locked is zero, and then both grab the lock by executing line 26. At this point, two
different CPUs hold the lock, which violates the mutual exclusion property. Rather
than helping us avoid race conditions, this implementation of acquire has its own
race condition. The problem here is that lines 25 and 26 executed as separate actions.
In order for the routine above to be correct, lines 25 and 26 must execute in one
atomic (i.e., indivisible) step.    

为了把25,26行变为一行,可以使用`xchgl`汇编指令,它原子地交换两个寄存器或者内存寄存器的内容.  
`xchgl`的原理是:x86提供了一个指令前缀`lock`(0xf0),当检测到这个前缀时,就"锁定"内存总线,知道这条指令执行完成为止.因此在执行`xchgl`时,其他处理器不能访问这个内存单元.(参考深入理解linux内核-内核同步-原子操作)    
其他的解释:https://zhuanlan.zhihu.com/p/33445834     
JOS的实现中`xchg()`封装了`xchgl`指令:
```
void
spin_lock(struct spinlock *lk)
{
	// The xchg is atomic.
	// It also serializes, so that reads after acquire are not
	// reordered before it. 
	while (xchg(&lk->locked, 1) != 0)
		asm volatile ("pause");
}
```
`asm volatile ("pause");`的作用是提高性能,参见https://c9x.me/x86/html/file_module_x86_id_232.html   
https://kb.cnblogs.com/page/105657/    
http://web.cecs.pdx.edu/~alaa/courses/ece587/spring2012/notes/memory-ordering.pdf   
在这四个地方应该应用这个大内核锁:
>In i386_init(), acquire the lock before the BSP wakes up the other CPUs.
>
>In mp_main(), acquire the lock after initializing the AP, and then call sched_yield() to start running environments on this AP.
>
>In trap(), acquire the lock when trapped from user mode. To determine whether a trap happened in user mode or in kernel mode, check the low bits of the tf_cs.
>In env_run(), release the lock right before switching to user mode. Do not do that too early or too late, otherwise you will experience races or deadlocks.

> Exercise 5. Apply the big kernel lock as described above, by calling lock_kernel() and unlock_kernel() at the proper locations.   

在对应位置加入`lock_kernel();`或者`unlock_kernel();`就行.      


>Question 2
>It seems that using the big kernel lock guarantees that only one CPU can run the kernel code at a time. Why do we still need separate kernel stacks for each CPU? Describe a scenario in which using a shared kernel stack will go wrong, even with the protection of the big kernel lock.

因为在`_alltraps`到`lock_kernel()`的过程中(即引发中断进入内核态时和内核上锁之间),进程已经切换到了内核态,但并没有上内核锁,此时如果有其他CPU进入内核,如果用同一个内核栈,则`_alltraps`中保存的上下文信息会被破坏(因为切换中断时,指针会重置,被压栈的数据会被覆盖(或者两个cpu使用的段可能不同)),所以即使有大内核栈,CPU也不能用用同一个内核栈.同样的,解锁也是在内核态内解锁,在解锁到真正返回用户态这段过程中,也存在上述这种情况.   


## round-robin scheduling(轮询调度)
轮询调度算法的原理是每一次把来自用户的请求轮流分配给内部中的处理器,从1开始,直到N(内部处理个数),然后重新开始循环.
算法的优点是其简洁性,它无需记录当前所有连接的状态,所以它是一种无状态调度.   
JOS的round-robin:
* `kern/schec.c`里的`sched_yield()`函数负责挑选一个新的进程运行,因此它可以用来让出cpu.它循环线性搜索`envs[]`里的进程,对遇到的第一个`ENV_RUNNABLE`进程调用`env_run()`.
* `sched_yield()`绝对能在两个cpu上运行同一个进程.它能从进程的状态`ENV_RUNNABLE`分辨一个进程现在运行在某个cpu(可能是现在这个)
* 我们已经实现了一个系统调用`sys_yield()`,用户进程可以调用它来执行内核的`sched_yield()`,然后自动放弃cpu以运行不同的进程.
**exercise 6**  
>Implement round-robin scheduling in sched_yield() as described above. Don't forget to modify syscall() to dispatch sys_yield().  

在`kern/sched.c`下修改：  
```c
// Choose a user environment to run and run it.
void
sched_yield(void)
{
	struct Env *idle;

	// Implement simple round-robin scheduling.
	//
	// Search through 'envs' for an ENV_RUNNABLE environment in
	// circular fashion starting just after the env this CPU was
	// last running.  Switch to the first such environment found.
	//
	// If no envs are runnable, but the environment previously
	// running on this CPU is still ENV_RUNNING, it's okay to
	// choose that environment.
	//
	// Never choose an environment that's currently running on
	// another CPU (env_status == ENV_RUNNING). If there are
	// no runnable environments, simply drop through to the code
	// below to halt the cpu.

	// LAB 4: Your code here.
	int index = 0;
	if (curenv!=NULL)
	{
		index = ENVX(curenv->env_id);
	}
	//从0开始,因为curenv->env_status==ENV_RUNNING
	for (int i = 0; i < NENV; i++)
	{
		index += i;
		index %= NENV;
		if(envs[index].env_status==ENV_RUNNABLE)
		{
			env_run(&envs[index]);
		}
	}
	if(curenv&&curenv->env_status==ENV_RUNNING)
	{
		env_run(curenv);
	}
		// sched_halt never returns
		sched_halt();
}
```
再在`kern/syscall.c`下dispatch`sched_yield()`：
```c
case SYS_yield:
		sys_yield();
		ret= 0;
		break;
```
>Question  
>3. In your implementation of env_run() you should have called lcr3(). Before and after the call to lcr3(), your code makes references (at least it should) to the variable e, the argument to env_run. Upon loading the %cr3 register, the addressing context used by the MMU is instantly changed. But a virtual address (namely e) has meaning relative to a given address context--the address context specifies the physical address to which the virtual address maps. Why can the pointer e be dereferenced both before and after the addressing switch?  

在链接时，链接器把变量的虚拟地址链接到`KERNBASE`以上，在`bootstrap`时硬编码了一个页表，把初始4MB映射到`KERNBASE`开始的4MB，因此在`lcr3()`之前和之后，这个映射都是一样的。  
>4.Whenever the kernel switches from one environment to another, it must ensure the old environment's registers are saved so they can be restored properly later. Why? Where does this happen?  
这样才能恢复上下文，当任务切换回来时能正确运行。  
### System calls for environment creation  
尽管内核现在可以在多个用户级别的环境中运行和切换，但仍限于内核最初设置的运行环境。现在你要实现必要的JOS系统调用，以允许用户环境创建和启动其他新的用户环境。   
Unix提供fork()系统调用作为其过程创建原语。Unixfork()复制调用进程（父进程）的整个地址空间，以创建一个新进程（子进程）。从用户空间可观察到的两者之间的唯一区别是它们的进程ID和父进程ID（由getpid和返回getppid）。在父级中， fork()返回子级的进程ID，而在子级中，fork()返回0。默认情况下，每个进程都获得自己的专用地址空间，并且另一个进程对内存的修改对其他人都不可见。  
你将提供一组不同的，更原始的JOS系统调用，以创建新的用户模式环境。通过这些系统调用fork()，除了创建环境的其他样式之外，你还可以完全在用户空间中实现类似Unix的功能。你将为JOS编写的新系统调用如下：  
`sys_exofork`：  
该系统调用创建了一个几乎空白的新环境：在其地址空间的用户部分中未映射任何内容，并且该环境不可运行。`sys_exofork`调用时，新环境将具有与父环境相同的寄存器状态。在父进程中，`sys_exofork` 将返回`envid_t`新创建的环境（如果环境分配失败，则返回负错误代码）。但是，在子进程中，它将返回0。（由于子进程开始时标记为不可运行，sys_exofork因此，直到父代通过使用....标记子代可显式允许该子代之前，它 才真正返回子代。）
`sys_env_set_status`：  
将指定环境的状态设置为ENV_RUNNABLE或ENV_NOT_RUNNABLE。一旦其地址空间和寄存器状态已完全初始化，此系统调用通常用于标记准备运行的新环境。
`sys_page_alloc`：  
分配一页物理内存，并将其映射到给定环境的地址空间中的给定虚拟地址。
`sys_page_map`：  
将一个页面映射（而不是页面的内容！）从一个环境的地址空间复制到另一个环境，保留内存共享安排，以便新映射和旧映射都引用同一物理内存页面。
`sys_page_unmap`：  
取消映射在给定环境中映射到给定虚拟地址的页面。
对于上面所有接受环境ID的系统调用，JOS内核都支持以下约定：值0表示“当前环境”。本公约对实现envid2env() 在克恩/ env.c。

我们fork() 在测试程序user / dumbfork.c中提供了类Unix的非常原始的实现。该测试程序使用上述系统调用来创建和运行带有其自身地址空间副本的子环境。然后，使用sys_yield 与上一个练习相同的方法来回切换两个环境。父级在10次迭代后退出，而子级在20次迭代后退出。






问题:
# Call mp_main().  (Exercise for the reader: why the indirect call?)
	#无页表?
	movl    $mp_main, %eax
	call    *%eax
分页开启前是怎么寻址的?

```
//复习实模式寻址:
# Each non-boot CPU ("AP") is started up in response to a STARTUP
# IPI from the boot CPU.  Section B.4.2 of the Multi-Processor
# Specification says that the AP will start in real mode with CS:IP
# set to XY00:0000, where XY is an 8-bit value sent with the
# STARTUP. Thus this code must start at a 4096-byte boundary.
#
//为什么?
# Because this code sets DS to zero, it must run from an address in
# the low 2^16 bytes of physical memory.
#
# boot_aps() (in init.c) copies this code to MPENTRY_PADDR (which
# satisfies the above restrictions).  Then, for each AP, it stores the
# address of the pre-allocated per-core stack in mpentry_kstack, sends
# the STARTUP IPI, and waits for this code to acknowledge that it has
# started (which happens in mp_main in init.c).
# This code is similar to boot/boot.S except that
#    - it does not need to enable A20
//为什么?
#    - it uses MPBOOTPHYS to calculate absolute addresses of its
#      symbols, rather than relying on the linker to fill them

```

