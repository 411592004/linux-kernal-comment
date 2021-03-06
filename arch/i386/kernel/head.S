/*
 *  linux/arch/i386/head.S
 *
 *  Copyright (C) 1991, 1992  Linus Torvalds
 */
/*
	The PDF documents about understanding Linux Kernel 1.2 are made by Liu Yihao
	这份学习Linux内核的PDF文档由刘以浩同学整理完成
	包含了作者在学习内核过程中搜集到的大量有关Linux
	内核的知识和自己的一些理解以及注释
	当然，最宝贵的还是这份原生的内核代码
	NOTE：如果在阅读过程中遇到什么问题，欢迎和我交流讨论
	Email：liuyihaolovem@163.com
*/
/*
 *  head.S contains the 32-bit startup code.
 */

.text
.globl _idt,_gdt,
.globl _swapper_pg_dir,_pg0
.globl _empty_bad_page
.globl _empty_bad_page_table
.globl _empty_zero_page
.globl _floppy_track_buffer

#define __ASSEMBLY__
#include <linux/tasks.h>
#include <linux/fd.h>
#include <asm/segment.h>

#define CL_MAGIC_ADDR	0x90020
#define CL_MAGIC	0xA33F
#define CL_BASE_ADDR	0x90000
#define CL_OFFSET	0x90022

/*
 * swapper_pg_dir is the main page directory, address 0x00001000 (or at
 * address 0x00101000 for a compressed boot).
 */

/*
	swapper_pg_dir是一个很重要的东西，它是所有进程内核空间的页表的模板
	在linux中，任何进程在内核空间就不分彼此了，所有的进程都会公用一份内核空间的内存映射，
	因此，内核空间是所有进程共享的，每当一个新的进程建立的时候，都会将swapper_pg_dir的768项
	以后的信息全部复制到新进程页目录的768项以后，代表内核空间。
*/
/*
	在Linux中，每个用户进程都可以访问4GB的线性地址空间。其中0x0~0xBFFFFFFF的3GB空间为用户态空间，
	用户态进程可以直接访问。从0xC0000000~0x3FFFFFFF的1GB空间为内核态空间，存放内核访问的代码和数
	据，用户态进程不能直接访问。当用户进程通过中断或系统调用访问内核态空间时，会触发X86的特权级转
	换（从特权级3切换到特权级0），即从用户态切换到内核态。 

	内核态虚拟空间从3GB到3GB+4MB的一段（对应进程页目录第768项指引的页表），被映射到物理地址0x0~0x3FFFFF（4MB）。
	因此，进程处于内核态时，只要通过访问3GB到3GB+4MB就可访问物理内存的低4MB空间。所有进程从3GB到4GB的线性空间都
	是一样的，由同样的页目录项，同样的页表，映射到相同的物理内存段。Linux以这种方式让内核态进程共享代码和数据。
*/

/*
	将段寄存器DS、ES、GS和FS用__KERNEL_DS（0x18，include/asm-i386/segment.h）来初始化
	（其作用是将定位到GDT中的第三项（内核数据段），并设置对该段的操作特权级为0）
*/
startup_32:
	cld
	movl $(KERNEL_DS),%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	mov %ax,%gs
	lss stack_start,%esp	//设置系统堆栈
/*
 * Clear BSS first so that there are no surprises...
 */
	xorl %eax,%eax
	movl $__edata,%edi
	movl $__end,%ecx
	subl %edi,%ecx
	cld
	rep
	stosb
/*
 * start system 32-bit setup. We need to re-do some of the things done
 * in 16-bit mode for the "real" operations.
*/
	call setup_idt	//调用设置中断描述符表子程序
	//eax初值为0，然后加1后为1.将eax赋值给0x000000的内存地址，即为内存首地址0。
	//然后再将内存0x100000(刚好超过2^20=1M)的值和eax比较，如果A20没打开，则对于访问高于1M地址的内容，会自动环绕，即对1M取模。
	//0x100000取模后即为0，故访问0x100000地址就是访问地址0.所以，如果是则说明A20没打开，eax的值与0x100000处的值应该是相等的。
	xorl %eax,%eax
1:	incl %eax		# check that A20 really IS enabled
	movl %eax,0x000000	# loop forever if it isn't
	cmpl %eax,0x100000
	je 1b
/*
 * Initialize eflags.  Some BIOS's leave bits like NT set.  This would
 * confuse the debugger if this code is traced.
 * XXX - best to initialize before switching to protected mode.
 */
//eflags由于各种计算的原因，很多标识已经不为0了!!!
	pushl $0
	popfl
/*
 * Copy bootup parameters out of the way. First 2kB of
 * _empty_zero_page is for boot parameters, second 2kB
 * is for the command line.
 */
/*初始化empty_zero_page：该页的前2KB空间用来存储setup.s保存在内存参数区的来自BIOS的系统硬件参数；后2KB空间作为命令行缓冲区*/
//将0x90000代码中的2k东西拷贝到empty_zero_page开始的2K处,同时将empty_zero_page随后的2K清零
	movl $0x90000,%esi
	movl $_empty_zero_page,%edi
	movl $512,%ecx
	cld
	rep
	movsl
	//随后的2K空间清零
	xorl %eax,%eax
	movl $512,%ecx
	rep
	stosl
	//判断90020H的值是否为0xA33F(通过页表0找到该地址)，从而判断是否包含有 命令行参数
	cmpw $(CL_MAGIC),CL_MAGIC_ADDR 
	jne 1f
	//执行到这里，说明命令行参数不为0,则将命令行参数复制到empty_zero_page页面后2K空间中
	movl $_empty_zero_page+2048,%edi
	movzwl CL_OFFSET,%esi
	addl $(CL_BASE_ADDR),%esi
	movl $2048,%ecx
	rep
	movsb
1:
/* check if it is 486 or 386. */
/*
 * XXX - this does a lot of unnecessary setup.  Alignment checks don't
 * apply at our cpl of 0 and the stack ought to be aligned already, and
 * we don't need to preserve eflags.
 */
//根据CPU的型号选择置位AM, WP, NE 和 MP
	movl $3,_x86
	pushfl			# push EFLAGS
	popl %eax		# get EFLAGS
	movl %eax,%ecx		# save original EFLAGS
	xorl $0x40000,%eax	# flip AC bit in EFLAGS
	pushl %eax		# copy to EFLAGS
	popfl			# set EFLAGS
	pushfl			# get new EFLAGS
	popl %eax		# put it in eax
	xorl %ecx,%eax		# change in flags
	andl $0x40000,%eax	# check if AC bit changed
	je is386
	movl $4,_x86
	movl %ecx,%eax
	xorl $0x200000,%eax	# check ID flag
	pushl %eax
	popfl			# if we are on a straight 486DX, SX, or
	pushfl			# 487SX we can't change it
	popl %eax
	xorl %ecx,%eax
	andl $0x200000,%eax
	je is486
isnew:	pushl %ecx		# restore original EFLAGS
	popfl
	/* get processor type */
	movl $1, %eax		# Use the CPUID instruction to 
	.byte 0x0f, 0xa2	# check the processor type
	movb %al, %cl		# save reg for future use
	andb $0x0f,%ah		# mask processor family
	movb %ah, _x86
	andb $0xf0, %eax	# mask model
	shrb $4, %al
	movb %al, _x86_model
	andb $0x0f, %cl		# mask mask revision
	movb %cl, _x86_mask
	movl %edx, _x86_capability
	/* get vendor info */
	xorl %eax, %eax			# call CPUID with 0 -> return vendor ID
	.byte 0x0f, 0xa2		# CPUID
	movl %ebx, _x86_vendor_id	# lo 4 chars
	movl %edx, _x86_vendor_id+4	# next 4 chars
	movl %ecx, _x86_vendor_id+8	# last 4 chars

	movl %cr0,%eax		# 486+
	andl $0x80000011,%eax	# Save PG,PE,ET
	orl $0x50022,%eax	# set AM, WP, NE and MP
	jmp 2f
is486:	pushl %ecx		# restore original EFLAGS
	popfl
	movl %cr0,%eax		# 486
	andl $0x80000011,%eax	# Save PG,PE,ET
	orl $0x50022,%eax	# set AM, WP, NE and MP
	jmp 2f
is386:	pushl %ecx		# restore original EFLAGS
	popfl
	movl %cr0,%eax		# 386
	andl $0x80000011,%eax	# Save PG,PE,ET
	orl $2,%eax		# set MP
2:	movl %eax,%cr0
	call check_x87
	call setup_paging	//对分页进行设置
	lgdt gdt_descr	//重新加载了新的GDT
	lidt idt_descr	//重新加载了新的IDT
//从Makefile可知道,tools/zSystem编译时用了编译参数-Ttext 100000，即表示tools/zSystem是
//从0x100000(即1M,2的20次方)处开始编址的，即boot/head.S的偏移地址为0x100000。
//那么$1f = 0x100000 + 符号1相对于system(即物理地址0x100000)的偏移量。
//根据KERNEL_CS所对应的内核代码段描述符可知，要jmp的虚拟地址 = 基地址0xC0000000 + $1f  = 0xC0100000 + 符号1相对于
//system(即物理地址0x100000)的偏移量
//然后根据内核分页将jmp的虚拟地址转化为物理地址，从虚拟地址的高10位可知，它对应页目录表的768个表项，即指向pg0页表。
//而根据分页机制可知，虚拟地址是对等映射到0～4M的物理内存的，所以,偏移地址0x100***,如0x100002等，都是对等映射到相同的物理地址。
//故，jmp能跳到正确的物理地址，即接下来的标号1处接着执行
	ljmp $(KERNEL_CS),$1f	//顺便重新加载了CS寄存器
1:	movl $(KERNEL_DS),%eax	# reload all the segment registers
	mov %ax,%ds		# after changing gdt.
	mov %ax,%es
	mov %ax,%fs
	mov %ax,%gs
	lss stack_start,%esp
	xorl %eax,%eax
	lldt %ax
	pushl %eax		# These are the parameters to main :-)
	pushl %eax
	pushl %eax
	cld			# gcc2 wants the direction flag cleared at all times
	call _start_kernel	//跳转到kernel/init/main.c中的start_kernel函数执行
L6:
	jmp L6			# main should never return here, but
				# just in case, we know what happens.

/*
 * We depend on ET to be correct. This checks for 287/387.
 */
check_x87:
	movb $0,_hard_math
	clts
	fninit
	fstsw %ax
	cmpb $0,%al
	je 1f
	movl %cr0,%eax		/* no coprocessor: have to set bits */
	xorl $4,%eax		/* set EM */
	movl %eax,%cr0
	ret
.align 2
1:	movb $1,_hard_math
	.byte 0xDB,0xE4		/* fsetpm for 287, ignored by 387 */
	ret

/*
 *  setup_idt
 *
 *  sets up a idt with 256 entries pointing to
 *  ignore_int, interrupt gates. It doesn't actually load
 *  idt - that can be done only after paging has been enabled
 *  and the kernel moved to 0xC0000000. Interrupts
 *  are enabled elsewhere, when we can be relatively
 *  sure everything is ok.
 */
/*
	有关IDT的初始化：这只是临时初始化IDT，进一步的操作在start_kernel中进行；用于表示IDT的变量（idt_table[ ]）
	在arch/i386/kenel/traps.c中定义，变量类型（desc_struct）定义在include/asm-i386/desc.h。IDT共有IDT_ENTRIES
	（256）个中断描述符，属性字均为0x8E00，每个中断描述符都指向同一个中断服务程序ignore_init。Ignore_int的功能仅
	仅是输出消息int_msg（"unknown interrupt"）。而IDTR的值为通过命令lidt idt_descr实现。通过在head.s中查看
	idt_descr的值可以计算得知，IDT的基地址为idt_table的地址，表长IDT_ENTRIES*8-1（0x7FF）
*/
//中断门的描述符内容为： 中断处理程序ignore_int地址的高16位 + 8E00 + 0010 + 中断处理程序ignore_int地址的低16位
//其中0x0010为中断处理程序ignore_int所在段的描述符，0x8E00为中断门的属性信息。
setup_idt:
	lea ignore_int,%edx	//将ingnore_int的有效地址（偏移值）-->edx寄存器
	movl $(KERNEL_CS << 16),%eax	//将选择符0x0010置于eax的高16位中
	//偏移值的低16位置于eax的低16位中，此时eax含有门描述符低4字节的内容
	movw %dx,%ax		/* selector = 0x0010 = cs */
	//此时edx含有门描述符的高4字节的内容
	movw $0x8E00,%dx	/* interrupt gate - dpl=0, present */

	lea _idt,%edi	// ---中断表的起始地址
	mov $256,%ecx	// ---循环256次，统一用默认的中断处理程序ignore_int来初始化256个中断。
rp_sidt:
	movl %eax,(%edi)
	movl %edx,4(%edi)
	addl $8,%edi
	dec %ecx
	jne rp_sidt
	ret


/*
 * Setup_paging
 *
 * This routine sets up paging by setting the page bit
 * in cr0. The page tables are set up, identity-mapping
 * the first 4MB.  The rest are initialized later.
 *
 * (ref: added support for up to 32mb, 17Apr92)  -- Rik Faith
 * (ref: update, 25Sept92)  -- croutons@crunchy.uucp 
 * (ref: 92.10.11 - Linus Torvalds. Corrected 16M limit - no upper memory limit)
 */
/*
	页目录的初始化：页目录由变量swapper_pg_dir表示，共有1024个页目录项。其第0项和第768项均指向pg0（第0页），
	初始化值为0x00102007（根据其高20bits的值0x102换算：0x102*4KB=0x102000，第0页紧跟页目录后，物理地址为
	0x102000），由此可知，Linux 4GB空间中的虚拟地址0x0和0xBFFFFFFF（3GB）均由pg0映射
	（物理地址0x0~0x3FFFFF（4MB））；其他页目录项初始值为0x0
	
	 pg0的初始化：第n项对应第n页，属性为0x007；即第n项的初始化值的高20bits值为n，底12bits值为0x007；
	由此可见pg0映射了物理空间的低4MB空间
*/
.align 2
setup_paging:
	//对页目录表和_pg0页内存清零(一共两页大小)
	movl $1024*2,%ecx		/* 2 pages - swapper_pg_dir+1 page table */
	xorl %eax,%eax
	movl $_swapper_pg_dir,%edi	/* swapper_pg_dir is at 0x1000 */
	cld;rep;stosl	//循环清零,cld表示EDI自动每次加4
/* Identity-map the kernel in low 4MB memory for ease of transition */
//填写页目录表，分别填写了index为0和768的页表项。从gdt中可知道，kernel和user的段的基址分别为
//0xC0000000和0x00000000，高10位分别为1100 0000 00b和0000 0000 00b，即表示页目录表中的第768个页表项和第0个页表项。
//这样kernel和user的线性地址可以根据_pg0页表来转换为物理地址。即使内核线性地址和用户线性地址开始处都通过_pg0指向物理内存开始的4M
//"$_pg0+7"表示：0x00001007(保护模式下，偏移量为32位)，是页目录表中的第1 项。则第1 个页表所在的地址 = 0x00001007 & 0xfffff000 = 0x1000；
//第1 个页表的属性标志 = 0x00001007 & 0x00000fff = 0x07，表示该页存在、用户可读写。
//内核将0到4M的物理内存分别映射到了虚拟地址的0到4M和3G到3G+4M两个地方，而且过了初始化阶段到了最终的稳定页表
	movl $_pg0+7,_swapper_pg_dir		/* set present bit/user r/w */
/* But the real place is at 0xC0000000 */
//同时将该页表项也赋给swapper_pg_dir的第768个页表项(3072/4)，表示虚拟地址0xc0000000也指向pg0(因为它高10位是1100 0000 00b，即为十进制
//768，故0xc0000000对应于页目录表的第768个表项，即指向pg0)。
	movl $_pg0+7,_swapper_pg_dir+3072	/* set present bit/user r/w */
//从页的最后一项开始填写每一个页表项。
//一页有1024个项，每个项大小为4bytes，故最后一个项为页的第4093到4096字节，即$_pg0+4092开始的四个字节。
//分页只映射4M大小，故对应于最后一个项的物理页的起始地址为4MB - 4096，再加上属性值7，即为4Mb - 4096 + 7，表示该页存在、用户可读写。
	movl $_pg0+4092,%edi
	movl $0x03ff007,%eax		/*  4Mb - 4096 + 7 (r/w user,p) */
	std	//表示EDI自动减4
	//从后往前，开始填写每一个页表项。一个页表对应于4M的物理内存(2^10 * 2^12).
    //4M的物理内存，即为物理地址0X0000 0000 到 0X003F F000
1:	stosl			/* fill the page backwards - more efficient :-) */
	subl $0x1000,%eax	//每填完一个页表项后，一个页表项对应一物理页，故对应的物理内存的地址就减少
	jge 1b	//如果小于0，则表明所有的页表项已经填完了
	cld
	movl $_swapper_pg_dir,%eax	//用0x101000初始化CR3（页目录swapper_pg_dir的地址）
	movl %eax,%cr3			/* cr3 - page directory start */
	movl %cr0,%eax
	//在此之前还未启动分页机制，所以之前使用的是物理地址
	//开启页面映射后，可以直接引用内核中的所有变量了
	orl $0x80000000,%eax	 //启动使用分页机制（cr0 的PG 标志，位31）
	movl %eax,%cr0		/* set paging (PG) bit */
	ret			/* this also flushes the prefetch-queue */

/*
 * page 0 is made non-existent, so that kernel NULL pointer references get
 * caught. Thus the swapper page directory has been moved to 0x1000
 *
 * XXX Actually, the swapper page directory is at 0x1000 plus 1 megabyte,
 * with the introduction of the compressed boot code.  Theoretically,
 * the original design of overlaying the startup code with the swapper
 * page directory is still possible --- it would reduce the size of the kernel
 * by 2-3k.  This would be a good thing to do at some point.....
 */
/*
*伪指令org用来规定目标程序存放单元的偏移量。比如，如果在源程序的第一条指令前用了如下指
*令： org 200h。那么，汇编程序会把指令指针的ip的值设成200h,即目标程序的第一个字节放
*在200h处，后面的内容则顺序存放，除非遇上另一个org 语句。
*另外需要注意的是，这里的200h是相对于当前section的偏移。例如这里的偏移就是0x2000，
*section就是.text， 而.text所在的地址就是0x100000，故这里其实就是地址0x102000。
*/
//org 0x1000说明了让系统将swapper_pg_dir加载到地址0x1000处
//内核最终搬到了0x100000处，那么swapper_pg_dir也就到了0x101000处
.org 0x1000	 //定义页目录表从偏移0x1000处开始
//http://www.eefocus.com/article/09-06/74897s.html 关于_swapper_pg_dir的介绍(<深入分析Linux内核源码>的章节)
_swapper_pg_dir:
/*
 * The page tables are initialized to only 4MB here - the final page
 * tables are set up later depending on memory size.
 */
.org 0x2000	//定义第一个页表从偏移0x2000处开始
_pg0:

.org 0x3000
_empty_bad_page:

.org 0x4000
_empty_bad_page_table:
/*
empty_zero_page中存放的是在操作系统的引导过程中所收集的一些数据，叫做引导参数。
因为这个页面开始的内容全为0，所以叫做“零页”，代码中常常通过宏定义ZERO_PAGE来引
用这个页面。不过，这个页面要到初始化完成，系统转入正常运行时才会用到
*/
.org 0x5000
_empty_zero_page:

.org 0x6000
/*
 * floppy_track_buffer is used to buffer one track of floppy data: it
 * has to be separate from the tmp_floppy area, as otherwise a single-
 * sector read/write can mess it up. It can contain one full cylinder (sic) of
 * data (36*2*512 bytes).
 */
_floppy_track_buffer:
	.fill 512*2*MAX_BUFFER_SECTORS,1,0
	
stack_start:
	.long _init_user_stack+4096
	.long KERNEL_DS

/* This is the default interrupt "handler" :-) */
int_msg:
	.asciz "Unknown interrupt\n"
.align 2
ignore_int:
	cld
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $(KERNEL_DS),%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	pushl $int_msg
	call _printk
	popl %eax
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret

/*
 * The interrupt descriptor table has room for 256 idt's
 */
.align 4
.word 0
//idt和gdt表的描述都是长6个字节，第一第二字节表示描述符表的长度值，
//第三个字节到第六个字节表示的是32位的线性基地址（即表中第一个描述符在内存的中的起始地址）
idt_descr:
	.word 256*8-1		# idt contains 256 entries
	.long 0xc0000000+_idt

.align 4
_idt:
	.fill 256,8,0		# idt is uninitialized //从当前地址开始连续填充256个size大小为8且value为0的数值

.align 4
.word 0
gdt_descr:
	.word (8+2*NR_TASKS)*8-1
	.long 0xc0000000+_gdt
/*
*在Linux中，每个用户进程都可以访问4GB的线性地址空间。其中0x0~0xBFFFFFFF的3GB空间为用户态空间，
*用户态进程可以直接访问。从0xC0000000~0x3FFFFFFF的1GB空间为内核态空间，存放内核访问的代码和数据，
*用户态进程不能直接访问。当用户进程通过中断或系统调用访问内核态空间时，会触发X86的特权级转换（从特权级3切换到特权级0），
*即从用户态切换到内核态。
*/

//从0xC0000000~0x3FFFFFFF的1GB空间为内核态空间，存放内核访问的代码和数据。所以，kernel的代码段和数据段的基地址都是以0xC0000000开始的。

/*
	有关GDT的初始化：GDT共有GDT_ENTRIES个段描述符。GDT_ENTRIES的计算公式为：12+2*NR_TASKS。
	其中12表示前面提到的Linux在GDT中保留的12项，NR_TASKS（512）指系统设定容纳的进程数，定义
	在include/linux/tasks.h。GDT在head.s直接分配存储单元（标号为gdt_table）。GDTR的值通过命
	令lgdt gdt_descr实现。通过在head.s中查看gdt_descr的值可以计算得知，GDT的基地址为gdt_table
	的地址，表长GDT_ENTRIES*8-1（0x205F）
*/
/*
 * This gdt setup gives the kernel a 1GB address space at virtual
 * address 0xC0000000 - space enough for expansion, I hope.
 */
.align 4	//向后移动位置计数器至4的倍数

//伪指令.quad将其后面的参数都汇编成为8字节的整数

_gdt:
	.quad 0x0000000000000000	/* NULL descriptor */
	.quad 0x0000000000000000	/* not used */
	.quad 0xc0c39a000000ffff	/* 0x10 kernel 1GB code at 0xC0000000 */
	.quad 0xc0c392000000ffff	/* 0x18 kernel 1GB data at 0xC0000000 */
	.quad 0x00cbfa000000ffff	/* 0x23 user   3GB code at 0x00000000 */
	.quad 0x00cbf2000000ffff	/* 0x2b user   3GB data at 0x00000000 */
	.quad 0x0000000000000000	/* not used */
	.quad 0x0000000000000000	/* not used */
	.fill 2*NR_TASKS,8,0		/* space for LDT's and TSS's etc */
