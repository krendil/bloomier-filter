module mapstore;

import std.algorithm;
import std.array;
import std.math;
import std.mmfile;
import std.range;
import std.typecons;

debug import std.stdio;

import ngramstore;
import util;

public class MapStore : NgramStore {

	MmFile file;

	uint[string] store;

	public void populate(string filename) {

		file = new MmFile(filename);
		auto ngrams = mMapReadNgrams(file)
			.filter!( (n) => (n[1] > 0) );

		//debug writefln( "Read %s ngrams", ngrams.length );
		debug(LoadOnly) return;

		foreach( key, val; ngrams ) {
			store[key] = val;
		}

		file = null;

	}

	bool boolGet(string key, out uint value) {
		uint* val = key in store;
		if( val !is null ) {
			value = *val;
			return true;
		}
		return false;
	}

	uint exceptionGet(string key) {
		return store[key];
	}

	ulong getTotalSize() {
		return getTrueSize!uint(store);
	}
}

public class QuartMapStore : NgramStore {

	import std.numeric;
	import core.memory;

	/**
	 * Define a custom 8-bit floating point type, that can only store positive numbers,
	 * has a maximum precision of 1/32, and a maximum value of ~255 (I think)
	 */
	alias uquart = CustomFloat!(5, 3, CustomFloatFlags.storeNormalized | CustomFloatFlags.allowDenorm, 0);

	MmFile file;

	uquart[string] store;

	public void populate(string filename) {

		file = new MmFile(filename);
		auto ngrams = mMapReadNgrams(file)
			.filter!( (n) => (n[1] > 0) )
			.map!( (n) => tuple(n[0], cast(uquart)log2(n[1])) );

		//debug writefln( "Read %s ngrams", ngrams.length );
		debug(LoadOnly) return;

		foreach( key, val; ngrams ) {
			store[key] = val;
		}

		file = null;

	}

	bool boolGet(string key, out uint value) {
		uquart* val = key in store;
		if( val !is null ) {
			value = cast(uint)(2 ^^ *val);
			return true;
		}
		return false;
	}

	uint exceptionGet(string key) {
		return cast(uint)(2 ^^ store[key]);
	}

	ulong getTotalSize() {
		return getTrueSize!uquart(store);
	}
}
