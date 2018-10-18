//
//  ReferenceRandomGenerators.h
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
//  Copyright © 2015 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and distribute this software for any purpose with or without
//  fee is hereby granted, provided that the above copyright notice and this permission notice
//  appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS
//  SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
//  AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
//  NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
//  OF THIS SOFTWARE.
//

#ifndef ReferenceRandomGenerators_h
#define ReferenceRandomGenerators_h

#import <stdint.h>

typedef struct {
	uint64_t s[4];
} xoshiro_state;

uint64_t xoshiro_next(xoshiro_state *s);

struct mt19937_64 {
	unsigned long long mt[312];
	int mti;
};

void init_genrand64(struct mt19937_64* context, unsigned long long seed);
unsigned long long genrand64_int64(struct mt19937_64* context);
double genrand64_real1(struct mt19937_64* context);
double genrand64_real2(struct mt19937_64* context);

#endif
