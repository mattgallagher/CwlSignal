/* 
   A C-program for MT19937-64 (2004/9/29 version).
   Coded by Takuji Nishimura and Makoto Matsumoto.

   This is a 64-bit version of Mersenne Twister pseudorandom number
   generator.

   Before using, initialize the state by using init_genrand64(seed)  
   or init_by_array64(init_key, key_length).

   Copyright (C) 2004, Makoto Matsumoto and Takuji Nishimura,
   All rights reserved.                          

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

     1. Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

     2. Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

     3. The names of its contributors may not be used to endorse or promote 
        products derived from this software without specific prior written 
        permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

   References:
   T. Nishimura, ``Tables of 64-bit Mersenne Twisters''
     ACM Transactions on Modeling and 
     Computer Simulation 10. (2000) 348--357.
   M. Matsumoto and T. Nishimura,
     ``Mersenne Twister: a 623-dimensionally equidistributed
       uniform pseudorandom number generator''
     ACM Transactions on Modeling and 
     Computer Simulation 8. (Jan. 1998) 3--30.

   Any feedback is very welcome.
   http://www.math.hiroshima-u.ac.jp/~m-mat/MT/emt.html
   email: m-mat @ math.sci.hiroshima-u.ac.jp (remove spaces)
*/


#include <stdio.h>
#include <mach/mach.h>
#include <mach/mach_time.h>

#define NN 312
#define MM 156
#define MATRIX_A 0xB5026F5AA96619E9ULL
#define UM 0xFFFFFFFF80000000ULL /* Most significant 33 bits */
#define LM 0x7FFFFFFFULL /* Least significant 31 bits */

struct mt19937_64 {
	unsigned long long mt[NN];
	size_t mti;
};

/* initializes mt[NN] with a seed */
void init_genrand64(struct mt19937_64* context, unsigned long long seed)
{
    context->mt[0] = seed;
    for (context->mti=1; context->mti<NN; context->mti++)
        context->mt[context->mti] =  (6364136223846793005ULL * (context->mt[context->mti-1] ^ (context->mt[context->mti-1] >> 62)) + context->mti);
}

struct mt19937_64 init_genrand64_fromtime()
{
	struct mt19937_64 context;
	init_genrand64(&context, mach_absolute_time());
	return context;
}

/* initialize by an array with array-length */
/* init_key is the array for initializing keys */
/* key_length is its length */
void init_by_array64(struct mt19937_64* context, unsigned long long init_key[],
		     unsigned long long key_length)
{
    unsigned long long i, j, k;
    init_genrand64(context, 19650218ULL);
    i=1; j=0;
    k = (NN>key_length ? NN : key_length);
    for (; k; k--) {
        context->mt[i] = (context->mt[i] ^ ((context->mt[i-1] ^ (context->mt[i-1] >> 62)) * 3935559000370003845ULL))
          + init_key[j] + j; /* non linear */
        i++; j++;
        if (i>=NN) { context->mt[0] = context->mt[NN-1]; i=1; }
        if (j>=key_length) j=0;
    }
    for (k=NN-1; k; k--) {
        context->mt[i] = (context->mt[i] ^ ((context->mt[i-1] ^ (context->mt[i-1] >> 62)) * 2862933555777941757ULL))
          - i; /* non linear */
        i++;
        if (i>=NN) { context->mt[0] = context->mt[NN-1]; i=1; }
    }

    context->mt[0] = 1ULL << 63; /* MSB is 1; assuring non-zero initial array */ 
}

/* generates a random number on [0, 2^64-1]-interval */
unsigned long long genrand64_int64(struct mt19937_64* context)
{
    size_t i;
    size_t j;
    unsigned long long result;

    if (context->mti >= NN) {/* generate NN words at one time */
		size_t mid = NN / 2;
		unsigned long long stateMid = context->mt[mid];
		unsigned long long x;
		unsigned long long y;

		/* NOTE: this "untwist" code is modified from the original to improve
		 * performance, as described here:
		 * http://www.cocoawithlove.com/blog/2016/05/19/random-numbers.html
		 * These modifications are offered for use under the original icense at
		 * the top of this file.
		 */
		for (i = 0, j = mid; i != mid - 1; i++, j++) {
			x = (context->mt[i] & UM) | (context->mt[i + 1] & LM);
			context->mt[i] = context->mt[i + mid] ^ (x >> 1) ^ ((context->mt[i + 1] & 1) * MATRIX_A);
			y = (context->mt[j] & UM) | (context->mt[j + 1] & LM);
			context->mt[j] = context->mt[j - mid] ^ (y >> 1) ^ ((context->mt[j + 1] & 1) * MATRIX_A);
		}
		x = (context->mt[mid - 1] & UM) | (stateMid & LM);
		context->mt[mid - 1] = context->mt[NN - 1] ^ (x >> 1) ^ ((stateMid & 1) * MATRIX_A);
		y = (context->mt[NN - 1] & UM) | (context->mt[0] & LM);
		context->mt[NN - 1] = context->mt[mid - 1] ^ (y >> 1) ^ ((context->mt[0] & 1) * MATRIX_A);

		context->mti = 0;
    }
	
    result = context->mt[context->mti];
    context->mti = context->mti + 1;

    result ^= (result >> 29) & 0x5555555555555555ULL;
    result ^= (result << 17) & 0x71D67FFFEDA60000ULL;
    result ^= (result << 37) & 0xFFF7EEE000000000ULL;
    result ^= (result >> 43);

    return result;
}

/* generates a random number on [0, 2^63-1]-interval */
long long genrand64_int63(struct mt19937_64* context)
{
    return (long long)(genrand64_int64(context) >> 1);
}

/* generates a random number on [0,1]-real-interval */
double genrand64_real1(struct mt19937_64* context)
{
    return (genrand64_int64(context) >> 11) * (1.0/9007199254740991.0);
}

/* generates a random number on [0,1)-real-interval */
double genrand64_real2(struct mt19937_64* context)
{
    return (genrand64_int64(context) >> 11) * (1.0/9007199254740992.0);
}

/* generates a random number on (0,1)-real-interval */
double genrand64_real3(struct mt19937_64* context)
{
    return ((genrand64_int64(context) >> 12) + 0.5) * (1.0/4503599627370496.0);
}
