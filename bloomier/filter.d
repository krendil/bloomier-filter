module bloomier.filter;

import std.algorithm;
import std.conv;
import std.math;
import std.parallelism;
import std.random;
import std.range;
import std.traits;
import std.typecons;

import bloomier.bitstring;
import bloomier.stack;

debug import std.stdio;

//mToS is the ratio of m to the size of the set of keys according to:
//		B.S. Majewski, N.C. Wormald, G. Havas, and Z.J. Czech.
//1996. A family of perfect hashing methods. British
//Computer Journal, 39(6):547–554.
struct BloomierFilter(K, V, uint q, uint k = 3, float mToS = 1.23) 
{

private:
	uint m;

	BitString!q[] table;

	static if( isArray!K ) {
		uint seed;
		alias KE = ElementEncodingType!K;
		ulong hashPrime;
	} else {
		ulong[k] hashParamA;
		ulong[k] hashParamB;
		ulong hashPrime;
	}

	private BitString!q decode(K key) {
		return table[]
			.indexed(hash(key)[])
			.reduce!"a ^ b"
			^ fingerprint(key);
	}

	static if( isArray!K ) {

		private void makeHashFun(ulong n) {
			seed = unpredictableSeed();
			hashPrime = getPrime(n);
		}

		private uint[k] hash(K key) {
			uint[k] result;
			auto rand = Xorshift(seed);
			foreach(i; 0..k) {
				ulong hash = rand.uniform!uint();
				foreach(size_t j, KE e; key) {
					hash += e * rand.uniform!uint();
				}
				//debug writefln("%064b", hash);
				result[i] = (hash >> KE.sizeof*8) % m;
			}
			return result;
		}


	} else {

		private void makeHashFun(ulong n) {
			hashPrime = getPrime(n);
			foreach( i; 0..k ) {
				hashParamA[i] = uniform(0, hashPrime);
				hashParamB[i] = uniform(1, hashPrime);
				sHashParam = uniform(0, ulong.max);
			}
		}

		private uint[k] hash(K key) {
			uint[k] result;
			static if(isIntegral!K) {
				auto prehash = key;
			} else {
				auto prehash = typeid(K).getHash(&key);
			}
			foreach( i; 0..k ) {
				result[i] = (prehash * hashParamA[i] + hashParamB[i]) % hashPrime % m;
			}
			return result;
		}

	}

	private static uint[2] ctRandoms(uint seed, uint limit) {
		if(!__ctfe) {
			//We should only run this function at compile time
			assert(false);
		} else {
			Random r = Random(seed);
			return [uniform(1, limit, r), uniform(0, limit, r)];
		}
	}

	private BitString!q fingerprint(K key) {
		enum ulong mask = (1UL << q) - 1;
		//Give the seed as q, because it should be consistent, but kind of random
		//Can cast mask to uint, b/c if you truncate, it will be MAXINT
		enum ulong[2] a = ctRandoms(q, cast(uint)mask);
		//Turn various types into a hashable number
		auto prehash =  typeid(K).getHash(&key);
		return BitString!q((prehash * a[0] + a[1]) & mask);
	}

public:
	/**
	 * Uses O(n * m) memory, but is faster(?)
	 * keys.length <= m
	 */
	void populate(R)(R keyValues)
		if (isRandomAccessRange!R && hasLength!R && is(ElementType!R == Tuple!(K, V))) 
	{
		
		alias HashSpot = uint; //A hashing location
		alias KeyN = uint; //An index to a key
		alias Matching = Stack!(Tuple!(KeyN, HashSpot));

		m = cast(uint) ceil(keyValues.length * mToS);
		table.length = m;

		//Keys that have been assigned a location
		Matching matched;
		matched.capacity = keyValues.length;

		//Creates a matching between keys, and hash locations that only they
		//hash to
		bool createMatching(ref Matching matched) {

			matched.clear();

			auto graph = new Tuple!(KeyN, ubyte)[](m); //Stores a number of xor'd key indices

			debug writeln("Hashing...");
			debug(HashMax) size_t max;

			foreach(i, kv; taskPool.parallel(keyValues) ) {
				auto hs = hash(kv[0]);
				foreach(h; hs ) {
					graph[h][0] ^= cast(uint)i;
					graph[h][1]++;
					debug(HashMax) max = max > graph[h][1] ? max : graph[h][1];
				}
				debug(HashDetails) { writefln("%s hashes to %s", kv[0], hs); }
			}

			debug(HashMax) writefln("Most keys in a hash spot: %s", max);

			debug writeln("Finished hashing.");
			debug(HashDetails) foreach( i, pair; graph ) writefln( "%s: %08b, %s", i, pair[1], pair[0] );
			debug(HashOnly) return true;

			//Find all the locations that only one key hashes to,
			//And strain out the key, location pairs
			auto degreeOne = graph[]
				.zip(iota(m))
				.filter!( loc => loc[0][1] == 1 );

			do {
				auto dg1 = degreeOne.save;
				if(dg1.empty) return false;

				foreach( key, spot; dg1 ) {
					debug(MatchDetails) writefln( "Matched key %s to spot %s", keyValues[key[0]][0], spot );

					matched.push(tuple(key[0], spot));

					foreach(other; hash(keyValues[key[0]][0])) {
						graph[other][0] ^= key[0];
						graph[other][1]--;
					}
				}

				debug {
					writefln("Matched %s/%s", matched.length, keyValues.length);
				}

			} while( matched.length < keyValues.length );

			return true;
		}

		do {
			debug { writeln("Attempting to create matching"); }
			makeHashFun(m);
		} while(!createMatching(matched));

		debug { writeln("Finished matching"); }

		//Encode the matched pairs into the table
		foreach( i, k, spot; zip(iota(keyValues.length), matched[])) {
			auto spots = hash(keyValues[k][0]);
			void* rawVal = &keyValues[k][1];
			table[spot] = 
				table[]
					.indexed( spots[].filter!(a => a != spot) )
					.reduce!"a^b"
				^ *cast(UnsignedInt!(V.sizeof)*)(rawVal)
				^ fingerprint(keyValues[k][0]);
		}
	}

	/**
	 *  Returns the value associated with the given key.
	 * If the key is not present in the collection, throws an exception.
	 */
	V opIndex(K key) {
		BitString!q value = decode(key);
		if( !value.fitsIn!V ) {
			throw new Exception( "The collection does not contain key %s".format(key) );
		}
		V* casted = cast(V*)(value.rawPointer);
		return *casted;
	}


	/**
	 * Returns true if the key is present in the collection and, if so,
	 * puts the value assicated with the key into value
	 */
	bool contains(K key, out V value) {
		BitString!q decoded = decode(key);
		if( decoded.fitsIn!V ) {
			value = *cast(V*)(decoded.rawPointer);
			return true;
		}
		return false;
	}

	string toString() {
		import std.conv;
		import std.array;

		Appender!(char[]) appender;

		appender ~= format(
				"m: %s\nq: %s\nk: %s\n", m, q, k);

		//appender ~= format("a: %s\nb: %s\n", hashParamA, hashParamB);
		appender ~= format("seed: %s\n", seed);

		appender ~= "Table: \n";
		foreach( row; table ) {
			appender ~= format("%s\n", row);
		}
		return appender.data.to!string;
	}

	size_t getRealSize() {
		return typeof(this).sizeof + m*(BitString!q).sizeof;
	}	

}
unittest {

	import std.stdio;
	import std.conv;

	string[] keys = ["a", "b", "c", "d", "e", "f"];
	ubyte[] values = [1, 2, 3, 4, 5, 6];
	auto filter = BloomierFilter!(string, ubyte, 16).init;
	filter.populate(
		zip(keys, values)
	);

	writeln(filter);

	foreach( k, v; zip(keys, values) ) {
		writefln("%s : %s", k, v);
		writeln( filter.hash(k) );
		writeln( filter.fingerprint(k) );
	
	
		assert(filter[k] == v, 
				format("Error: value for key \"%s\" does not match value %s; got %s instead.",
					k, v, filter[k]));

		ubyte val;
		assert( filter.contains(k, val), "Error: falsely claimed '%k' not found".format(k) );
		assert( val == v, "Error: value for key \"%s\" does not match value %s; got %s instead."
							.format(k, v, val));
	}

	string[] bogusKeys = ["g", "h", "i", "j", "k", "l"];

	foreach( k; bogusKeys ) {
		try { 
			auto v = filter[k];
			assert(false, "Didn't throw exception on false key %s".format(k));
		} catch (Exception e) {}

		ubyte val;
		assert(!filter.contains(k, val));
	}


}

private void removeAll(T)(ref T[] haystack, T needle) {
	size_t hole = 0; // The last empty position
	size_t numRemoved = 0;
	for(int i = 0; i < haystack.length; i++) {
		while((i + numRemoved) < haystack.length && haystack[i + numRemoved] == needle) {
			numRemoved++;
		}
		if( i + numRemoved < haystack.length ) {
			haystack[i] = haystack[i + numRemoved];
		}
	}
	haystack.length -= numRemoved;
}

unittest {
	import std.conv;

	int[] nums = [1, 2, 1, 2, 3];
	removeAll(nums, 2);
	assert( nums == [1, 1, 3], "Error removing simple case, got " ~ nums.to!string);
	nums.removeAll(3);
	assert( nums == [1, 1], "Error removing last value, got " ~ nums.to!string);
	nums.removeAll(1);
	assert( nums == [], "Error removing all values, got " ~ nums.to!string );
}


/**
 * Returns a prime number that is greater than m.
 * Is is not necessairly the next greatest prime number.
 * In fact it usually just returns the largest prime number that fits in 64 bits.
 */
private ulong getPrime(ulong m) {
	//The largest prime number that fits in 63 bits
	//according to http://primes.utm.edu/lists/2small/0bit.html
	//Will usually be halfway between m and 2^64 (for small values of m)
	enum ulong P = (1UL << 63) - 25;
	if( m < P ) {
		return P;
	} else {
		return ulong.max; //Not really a prime, but it's a Mersenne number which is close enough, right?
	}
}

private template UnsignedInt(size_t size) {
	static if(size <= 8) {
		alias UnsignedInt = ubyte;
	} else static if(size <= 16) {
		alias UnsignedInt = ushort;
	} else static if(size <= 32) {
		alias UnsignedInt = uint;
	} else static if(size <= 64) {
		alias UnsignedInt = ulong;
	} else {
		static assert(0, "No int types big enough!");
	}
}

