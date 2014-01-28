module bloomier.bitstring;

import std.algorithm;
import std.traits;

import core.bitop;

debug import std.stdio;

/**
 * A constant length, statically allocated array of bits
 *
 */
struct BitString(ulong len) if(len > 0) {
	static if( len <= ubyte.sizeof * 8 ) {
		alias T = ubyte;
	} else static if( len <= ushort.sizeof * 8 ) {
		alias T = ushort;
	} else static if( len <= uint.sizeof * 8 ) {
		alias T = uint;
	} else static if( len <= size_t.sizeof * 8) {
		alias T = size_t;
	} else { //Too long to fit in a single word
		alias T = size_t[ ((len - 1) / (size_t.sizeof * 8)) + 1];
	}

	T data;

	@property ulong length() {
		return len;
	}

	template forwardBinary(string op) {
		static if(isArray!T) {
			enum forwardBinary = q{
				BitString!len result;
				result.data[] = this.data[] }~op~q{ other.data[];
			};
		} else {
			enum forwardBinary = "auto result = BitString(this.data "~op~" other.data);";
		}
	}

	auto opBinary(string op : "&")(BitString!len other) {
		mixin(forwardBinary!op);
		return result;
	}
	auto opBinary(string op : "|")(BitString!len other) {
		mixin(forwardBinary!op);
		return result;
	}
	auto opBinary(string op : "^")(BitString!len other) {
		mixin(forwardBinary!op);
		return result;
	}

	auto opBinary(string op : "^", U : ulong)(U other) {
		static if(isArray!T) {
			auto newData = data.dup;

			static if(U.sizeof <= size_t.sizeof) {
				newData[0] ^= other;
			} else {
				static assert(0);
			}

			return BitString(newData);
		} else {
			static assert( U.sizeof <= T.sizeof );
			return BitString(this.data ^ other);
		}
	}

	/**
	 * Get the state of a single bit.
	 * Order is left-to-right, so
	 * Most significant bit is at 0,
	 * and first array element is most significant.
	 */
	bool opIndex(size_t bit)
	in {
		assert(bit <= len);
	} body {
		static if(isArray!T) {

			enum wordlen = (size_t.sizeof * 8);
			auto element = bit / wordlen;
			size_t mask = 1L << (wordlen - 1);

			static if( len % wordlen != 0 ) { //The last element is not full
				if( element == data.length - 1 ) { //And we are actually indexing the last element
					mask = 1L << (len % wordlen - 1);
				} 
			}

			//return (data[element] & (mask >> (bit % wordlen))) != 0;
			auto offset = (bit % wordlen);
			auto newMask = (mask >> offset);
			auto bits = data[element];
			auto b = bits & newMask;
			return b != 0;

		} else {

			enum mask = 1L << (len - 1);
			return (data & (mask >> bit)) != 0;

		}
	}

	void opIndexAssign(bool value, size_t bit) 
	in {
		assert(bit <= len);
	} body {
		static if(isArray!T) {

			enum wordlen = (size_t.sizeof * 8);
			auto element = bit / wordlen;
			size_t mask = 1L << (wordlen - 1);

			static if( len % wordlen != 0 ) { //The last element is not full
				if( element == data.length - 1 ) { //And we are actually indexing the last element
					mask = 1L << (len % wordlen - 1);
				} 
			}

			if(!value) {
				data[element] = ~data[element];
			}

			data[element] |= (mask >> (bit % wordlen));

			if(!value) {
				data[element] = ~data[element];
			}

		} else {

			enum mask = 1L << (len - 1);
			if(!value) {
				data = ~data;
			}
			data |= (mask >> bit);
			if(!value) {
				data = ~data;
			}

		}
	}

	/**
	 * Returns the number of bits that are set
	 */
	@property
	public size_t setBits() {
		static if(isArray!T) {
			return data[]
				.map!(countBits!size_t)
				.reduce!"a + b";
		} else {
			return countBits(data);
		}
	}

	@property
	public void* rawPointer() {
		static if(isArray!T) {
			return data.ptr;
		} else {
			return &data;
		}
	}


	static size_t countBits(T)(T bits) if(isUnsigned!T) {
		static if( is(T : uint) ) {
			return popcnt(bits);
		} else { 
			return popcnt( cast(uint)(bits & 0xFFFF_FFFF) )
				+ popcnt( cast(uint)(bits >> 32) );
		}
	}

	public bool fitsIn(U)()
		if(isIntegral!U)
	{
		static if( isArray!T ) {

			auto usedBits = len % size_t.sizeof*8;
			auto lastValue = data[$-1];
			if( usedBits > 0 ) {
				lastValue >>= size_t.sizeof*8 - usedBits;
			}
			return !canFind!(n => n != 0)( data[0..$-2] )
				&& lastValue <= U.max;

		} else {
			return data <= U.max;
		}
	}


	public bool fitsIn(U)()
		if(!isIntegral!U)
	{
		static if( isArray!T ) {

			enum size_t wordSize = size_t.sizeof*8;

			enum size_t safeBits = realSize!U*8;

			foreach(i, word; data) {

				//The current word fits entirely within the target size
				if( len - i*wordSize <= safeBits ) {
					//If we get this far, we don't need to continue
					return true;

				//The current word partially fits within the target size
				} else if( len - (i+1)*wordSize <= safeBits ) {
					if( bsr(word) >= safeBits % wordSize ) {
						return false;
					} else {
						return true;
					}

				//The current word is outside the target size
				} else {
					if(word != 0) {
						return false;
					}
				}
			}
			assert(0); //Should not happen

		} else {
			if( data == 0 ) {
				return true;
			}

			return bsr(data) < realSize!U*8;
		}
	}


	public string toString() const
    {
		import std.string;
		import std.array;
		import std.conv;
		static if( isArray!T ) {
			Appender!(char[]) appender;
			foreach( chunk; data ) {
				appender ~= format("%0*b", size_t.sizeof*8, chunk);
			}
			return appender.data.to!string;
		} else {
			return format("%0*b", len, data);
		}
	}

}

/**
 * Struct sizes are aligned on word boundaries, so this function gets the
 * actual size of the members, excluding the padding.
 */
private static size_t realSize(U)() 
{
	static if(isAggregateType!U) {
		size_t ret;
		foreach( M; U.init.tupleof ) {
			ret += M.sizeof;
		}
		return ret;
	} else {
		return U.sizeof;
	}
}

unittest {
	import std.typetuple;
	import std.conv;

	alias BS = BitString;

	//Ensure BitString can be instatiated with the given sizes
	foreach( len ; TypeTuple!(3, 8, 10, 16, 25, 32, 48, 64, 65) ) {
		BS!len bs;
		assert(bs.length == len, "Error creating BitString with length "~len.to!string);
	}

	auto a = BS!8( 0b00110011 );
	auto b = BS!8( 0b01010101 );

	//Ensure bitwise ops work properly
	assert( (a & b) == BS!8( 0b00010001 ), "Bitwise AND failed, got "~(a&b).data.to!string);
	assert( (a | b) == BS!8( 0b01110111 ), "Bitwise OR failed, got "~(a|b).data.to!string);
	assert( (a ^ b) == BS!8( 0b01100110 ), "Bitwise XOR failed, got "~(a^b).data.to!string);

	//Ensure long bitstrings work properly
	BS!(size_t.sizeof*8 * 2) c;
	assert(c.data.length == 2);
	c = typeof(c)( [0b0011, 0b1100] );
	auto d = typeof(c)( [0b0101, 0b1010] );

	assert( (c & d) == typeof(c)( [0b0001, 0b1000] ), "Bitwise AND failed, got "~(a&b).data.to!string);
	assert( (c | d) == typeof(c)( [0b0111, 0b1110] ), "Bitwise OR failed, got "~(a|b).data.to!string);
	assert( (c ^ d) == typeof(c)( [0b0110, 0b0110] ), "Bitwise XOR failed, got "~(a^b).data.to!string);

	assert( !a[0], "Indexing false negative at index 0");
	assert( a[7], "Indexing false positive at index 7");

	assert( !c[0], "Indexing false positive at element 0, index 0");
	auto index = size_t.sizeof * 8 * 2 - 3; //Third to last bit
	assert( c[ index ], "Indexing false negative at element 1, index -3");

	BS!(ulong.sizeof*8 + 8) e; //Last element not full
	e = typeof(e)( [0x00_00_00_00, 0b11001100] );

	assert( e[64], "Indexing false negative at element 1, index +1");
	assert( !e[63], "Indexing false positive at element 0, index -1");
	assert( !e[70], "Indexing false positive at element 1, index +6");

	a[0] = true;
	assert( a[0], "Assigning true at index 0 failed");
	a[7] = false;
	assert( !a[7], "Assigning false to true at index 7 failed");

	c[index] = true;
	assert( c[index], "Assigning false to true at element 1, index -3 failed");
	c[index] = false;
	assert( !c[index], "Assigning true to false at element 1, index -3 failed");


	auto f = BitString!32(3);
	assert( f.fitsIn!ubyte , "Falsely claimed '3' can't fit in a ubyte.");
	auto g = BitString!32( 32768 );
	assert( !g.fitsIn!ubyte , "Falsely claimed '32768' can fit in a ubyte." );

	auto h = BitString!128(32768);
	assert( h.fitsIn!int , "Falsely claimed '32768' can't fit in an int (from an array)." );
	assert( !h.fitsIn!ubyte, "Falsely claimed '32768' can fit in a ubyte (from an array)." );

	struct Skinny {
		byte x;
	}
	assert( realSize!Skinny == 1 );

	struct Medium {
		long x;
	}
	assert( realSize!Medium == 8 );

	struct Fat {
		long x;
		short y;
	}
	assert( realSize!Fat == 10 );

	auto i = BitString!64(0x0000_0000_0000_0000UL);
	assert( i.fitsIn!Skinny, "Falsely claimed '0' can't fit in 8 bits." );
	assert( i.fitsIn!Medium, "Falsely claimed '0' can't fit in 64 bits." );
	assert( i.fitsIn!Fat, "Falsely claimed '0' can't fit in 80 bits." );

	auto j = BitString!64(0x0001_0000_0000_0000UL);
	assert( !j.fitsIn!Skinny, "Falsely claimed '2^48' can fit in 8 bits." );
	assert( j.fitsIn!Medium, "Falsely claimed '2^48' can't fit in 64 bits." );
	assert( j.fitsIn!Fat, "Falsely claimed '2^48' can't fit in 80 bits." );

	auto k = BitString!128([0x0000_0000_0000_0010UL, 0x0000_0000_0000_0000UL]);
	assert( !k.fitsIn!Medium(), "Falsely claimed '2^68' can fit in 64 bits." );
	assert( k.fitsIn!Fat(), "Falsely claimed '2^88' can't fit in 80 bits." );

	auto l = BitString!128([0x0001_0000_0000_0000UL, 0x0000_0000_0000_0000UL]);
	assert( !l.fitsIn!Fat, "Falsely claimed '2^112' can fit in 80 bits." );
}

