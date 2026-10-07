// SPDX-License-Identifier: GPL-2.0
/*
 * Store-buffering litmus test without BPF or a kernel in the loop, to isolate
 * the SB+cmpxchg "Never" violation seen under QEMU TCG with Zacas.
 *
 *   P0: OP(x, 0 -> 1); r0 = y;      P1: OP(y, 0 -> 1); r1 = x;
 *   forbidden (for a fully-ordered OP): r0 == 0 && r1 == 0
 *
 * OP is selected by argv[1]:
 *   plain        sd                                   (SB allowed: sanity check)
 *   amocas       amocas.d.aqrl                         (what the BPF JIT emits with Zacas)
 *   amocas_fence amocas.d.aqrl ; fence rw,rw
 *   jit_lrsc     lr.d ; bne ; sc.d.rl ; bnez ; fence rw,rw   (BPF JIT without Zacas)
 *   lrsc_aqrl    lr.d.aqrl ; bne ; sc.d.rl ; bnez     (seq_cst CAS mapping, no fence)
 *   amoswap      amoswap.d.aqrl                        (what QEMU's xchg helper is on riscv)
 *   gcc_cas      __atomic_compare_exchange_n(SEQ_CST)  (what QEMU's cmpxchg helper is)
 *   fence        sd ; fence rw,rw                      (SB forbidden: sanity check)
 *
 * Usage: sb_isolate MODE [iterations] [cpu0] [cpu1] [max-delay]
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LINE 64

static struct {
	volatile uint64_t x __attribute__((aligned(LINE)));
	volatile uint64_t y __attribute__((aligned(LINE)));
	volatile uint64_t r[2] __attribute__((aligned(LINE)));
} s;

/* Sense-reversing two-thread barrier. */
static int bar_count __attribute__((aligned(LINE)));
static int bar_sense __attribute__((aligned(LINE)));

static void barrier(int *local)
{
	*local = !*local;
	if (__atomic_fetch_add(&bar_count, 1, __ATOMIC_SEQ_CST) == 1) {
		__atomic_store_n(&bar_count, 0, __ATOMIC_RELAXED);
		__atomic_store_n(&bar_sense, *local, __ATOMIC_SEQ_CST);
	} else {
		while (__atomic_load_n(&bar_sense, __ATOMIC_SEQ_CST) != *local)
			;
	}
}

/*
 * Each op does "OP(mine, 0 -> 1); return *other" in one asm block, so under
 * QEMU the store side and the following load are translated together rather
 * than split by a call/return (whose TB lookup would drain store buffers).
 */
typedef uint64_t (*op_fn)(volatile uint64_t *mine, volatile uint64_t *other);

#define LD "\n\tld %[r], 0(%[o])"
#define OUT [r] "=&r"(r)
#define IN [m] "r"(mine), [o] "r"(other), [one] "r"(1UL)

static uint64_t op_plain(volatile uint64_t *mine, volatile uint64_t *other)
{
	uint64_t r;

	asm volatile("sd %[one], 0(%[m])" LD : OUT : IN : "memory");
	return r;
}

static uint64_t op_fence(volatile uint64_t *mine, volatile uint64_t *other)
{
	uint64_t r;

	asm volatile("sd %[one], 0(%[m])\n\tfence rw, rw" LD : OUT : IN : "memory");
	return r;
}

static uint64_t op_amocas(volatile uint64_t *mine, volatile uint64_t *other)
{
	uint64_t r, old = 0;

	asm volatile(".option push\n\t.option arch, +zacas\n\t"
		     "amocas.d.aqrl %[old], %[one], (%[m])\n\t"
		     ".option pop" LD
		     : OUT, [old] "+r"(old) : IN : "memory");
	return r;
}

static uint64_t op_amocas_fence(volatile uint64_t *mine, volatile uint64_t *other)
{
	uint64_t r, old = 0;

	asm volatile(".option push\n\t.option arch, +zacas\n\t"
		     "amocas.d.aqrl %[old], %[one], (%[m])\n\t"
		     "fence rw, rw\n\t"
		     ".option pop" LD
		     : OUT, [old] "+r"(old) : IN : "memory");
	return r;
}

/* What the BPF JIT emits for BPF_CMPXCHG without Zacas. */
static uint64_t op_jit_lrsc(volatile uint64_t *mine, volatile uint64_t *other)
{
	uint64_t r, tmp, fail;

	asm volatile("1:\tlr.d %[tmp], (%[m])\n\t"
		     "bnez %[tmp], 2f\n\t"
		     "sc.d.rl %[fail], %[one], (%[m])\n\t"
		     "bnez %[fail], 1b\n"
		     "2:\tfence rw, rw" LD
		     : OUT, [tmp] "=&r"(tmp), [fail] "=&r"(fail) : IN : "memory");
	return r;
}

/* GCC's seq_cst CAS mapping, written out by hand. */
static uint64_t op_lrsc_aqrl(volatile uint64_t *mine, volatile uint64_t *other)
{
	uint64_t r, tmp, fail;

	asm volatile("1:\tlr.d.aqrl %[tmp], (%[m])\n\t"
		     "bnez %[tmp], 2f\n\t"
		     "sc.d.rl %[fail], %[one], (%[m])\n\t"
		     "bnez %[fail], 1b\n"
		     "2:" LD
		     : OUT, [tmp] "=&r"(tmp), [fail] "=&r"(fail) : IN : "memory");
	return r;
}

static uint64_t op_amoswap(volatile uint64_t *mine, volatile uint64_t *other)
{
	uint64_t r, old;

	asm volatile("amoswap.d.aqrl %[old], %[one], (%[m])" LD
		     : OUT, [old] "=&r"(old) : IN : "memory");
	return r;
}

/* Exactly QEMU's qatomic_cmpxchg__nocheck(), followed by a plain load. */
static uint64_t op_gcc_cas(volatile uint64_t *mine, volatile uint64_t *other)
{
	uint64_t r, old = 0;

	__atomic_compare_exchange_n((uint64_t *)mine, &old, 1, 0,
				    __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
	asm volatile("ld %[r], 0(%[o])" : OUT : [o] "r"(other) : "memory");
	return r;
}

static const struct { const char *name; op_fn fn; } ops[] = {
	{ "plain", op_plain },		{ "fence", op_fence },
	{ "amocas", op_amocas },	{ "amocas_fence", op_amocas_fence },
	{ "jit_lrsc", op_jit_lrsc },	{ "lrsc_aqrl", op_lrsc_aqrl },
	{ "amoswap", op_amoswap },	{ "gcc_cas", op_gcc_cas },
};

static op_fn op;
static long iters;
static int cpus[2];
static long hist[4];
static int delay_max = 64;

static void *thread(void *arg)
{
	int id = (int)(intptr_t)arg, sense = 0;
	volatile uint64_t *mine = id ? &s.y : &s.x, *other = id ? &s.x : &s.y;
	cpu_set_t set;

	CPU_ZERO(&set);
	CPU_SET(cpus[id], &set);
	pthread_setaffinity_np(pthread_self(), sizeof(set), &set);

	uint64_t rnd = 0x9e3779b97f4a7c15ULL * (id + 1);

	for (long i = 0; i < iters; i++) {
		barrier(&sense);
		/*
		 * Independent random skew per thread, so that across iterations
		 * the two critical sections overlap at many relative offsets.
		 */
		rnd ^= rnd << 13; rnd ^= rnd >> 7; rnd ^= rnd << 17;
		for (volatile int d = (int)(rnd % delay_max); d > 0; d--)
			;
		s.r[id] = op(mine, other);
		barrier(&sense);
		if (id == 0) {
			hist[s.r[0] * 2 + s.r[1]]++;
			s.x = 0;
			s.y = 0;
		}
		barrier(&sense);
	}
	return NULL;
}

int main(int argc, char **argv)
{
	pthread_t t[2];

	if (argc < 2)
		goto usage;
	for (size_t i = 0; i < sizeof(ops) / sizeof(ops[0]); i++)
		if (!strcmp(argv[1], ops[i].name))
			op = ops[i].fn;
	if (!op)
		goto usage;
	iters = argc > 2 ? atol(argv[2]) : 1000000;
	cpus[0] = argc > 3 ? atoi(argv[3]) : 0;
	cpus[1] = argc > 4 ? atoi(argv[4]) : 1;
	delay_max = argc > 5 ? atoi(argv[5]) : 64;

	for (int i = 0; i < 2; i++)
		pthread_create(&t[i], NULL, thread, (void *)(intptr_t)i);
	for (int i = 0; i < 2; i++)
		pthread_join(t[i], NULL);

	printf("%-13s iters=%ld  (0,0)=%ld  (0,1)=%ld  (1,0)=%ld  (1,1)=%ld  forbidden-if-ordered=%ld\n",
	       argv[1], iters, hist[0], hist[1], hist[2], hist[3], hist[0]);
	return 0;

usage:
	fprintf(stderr, "usage: %s MODE [iters] [cpu0] [cpu1] [max-delay]\nmodes:", argv[0]);
	for (size_t i = 0; i < sizeof(ops) / sizeof(ops[0]); i++)
		fprintf(stderr, " %s", ops[i].name);
	fprintf(stderr, "\n");
	return 2;
}
