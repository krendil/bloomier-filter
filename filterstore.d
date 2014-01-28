module filterstore;

import bloomier.filter;

import std.algorithm;
import std.array;
import std.math;
import std.mmfile;
import std.numeric;
import std.typecons;


debug import std.stdio;

public import ngramstore;
import util;

public class FilterStore(size_t q = 63) : NgramStore {

	private BloomierFilter!(string, uint, q) filter;
	
	//Workaround to prevent file from being unmapped
	private MmFile file;

	public void populate(string ngramFile) {
	
		file = new MmFile(ngramFile);
		auto ngrams = mMapReadNgrams(file).array();

		debug writefln( "Read %s ngrams", ngrams.length );

		filter.populate(ngrams);

		file = null;

	}

	public bool boolGet(string key, out uint value) {
		return filter.contains(key, value);
	}

	public uint exceptionGet(string key) {
		return filter[key];
	}

	public ulong getTotalSize() {
		return filter.getRealSize();
	}
}

public class QuartFilterStore(size_t q = 16) : NgramStore {

	import std.numeric;
	import core.memory;

	/**
	 * Define a custom 8-bit floating point type, that can only store positive numbers,
	 * has a maximum precision of 1/32, and a maximum value of ~255 (I think)
	 */
	alias uquart = CustomFloat!(5, 3, CustomFloatFlags.storeNormalized | CustomFloatFlags.allowDenorm, 0);

	private BloomierFilter!(string, uquart, q) filter;

	//Workaround to prevent file from being unmapped
	private MmFile file;

	public void populate(string ngramFile) {
	
		file = new MmFile(ngramFile);
		auto ngrams = mMapReadNgrams(file)
			.filter!( (n) => (n[1] > 0) )
			.map!( (n) => tuple(n[0], cast(uquart)log2(n[1])) )
			.array();

		debug writefln( "Read %s ngrams", ngrams.length );
		debug(LoadOnly) return;

		filter.populate(ngrams);

		file = null;

	}

	public bool boolGet(string key, out uint value) {
		uquart stored;
		bool ret = filter.contains(key, stored);
		value = cast(uint)(2 ^^ stored);
		return ret;
	}

	public uint exceptionGet(string key) {
		return cast(uint)( 2 ^^ filter[key]);
	}

	public ulong getTotalSize() {
		return filter.getRealSize();
	}

}
