module util;

import std.algorithm;
import std.conv;
import std.mmfile;
import std.parallelism;
import std.range;
import std.typecons;
debug import std.stdio;
/+
auto readNgrams(string ngramFile) {

	return File(ngramFile)
		.byLine
		.map!( (char[] line) {
				uint count = parse!uint(line);
				string ngram = line[1..$].idup;
				return tuple(ngram, count);
				} );
}+/

auto mMapReadNgrams(MmFile file) {

	return (cast(string)file[])
		.splitter('\n')
		.filter!( str => !(str.length == 0) )
		.map!( (string line) {
				uint count = parse!uint(line);
				return tuple(line[1..$], count);
			} );

}

size_t getTrueSize(V, T : V[string])( T aArray ) {

//	import std.traits;

	import rt.aaA;

	size_t size = 0;
	size += AA.sizeof;
	size += BB.sizeof;

	auto aa = cast(AA*) &aArray;
	auto bb = (*aa).a;

	size += size_t.sizeof * bb.b.length;

	foreach( aaA* node; bb.b ) {
		
		//Have to do pointer wizardry, because the current AA implementation is a bit arcane
		for( ; node !is null; node = node.next ) {
			size += aaA.sizeof;
			size += V.sizeof;
			size += string.sizeof;
			string key = *(cast(string*)(node + 1));
			//debug writeln(key);
			size += key.length;
		}

	}
	return size;
}

/+
/**
 * Struct definitions from druntime module rt.aaA
 */
struct aaA
{
    aaA *next;
    size_t hash;
    /* key   */
    /* value */
}

struct BB
{
    aaA*[] b;
    size_t nodes;       // total number of aaA nodes
    //TypeInfo keyti;     // TODO: replace this with TypeInfo_AssociativeArray when available in _aaGet()
    aaA*[4] binit;      // initial value of b[]
}

struct AA
{
    BB* a;
}
+/
