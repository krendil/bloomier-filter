module benchmark;

import std.datetime;
import std.conv;
import std.stdio;

import core.memory;

import filterstore;
import mapstore;

immutable string[] ngramFiles = [
	"data/1k_1gram.txt",
	"data/10k_1gram.txt",
	"data/100k_1gram.txt",
	"data/1m_1gram.txt",
	"data/wp_1gram.txt",
	"data/50m_2gram.txt",
	"data/wp_2gram.txt"
	];

	immutable double[] ngramAmounts = 
	[1000, 10_000, 100_000, 1_000_000, 7_955_768, 50_000_000, 92_650_277];

	//The first four queries are from the top 1k 1grams,
	//The next four queries are from the top 50m 2grams
	immutable string[] queries = [
	",",
	"is",
	"active",
	"BBC",
	"motion\tmachines",
	"everything\ther",
	"naturally\tlike",
	"announces\tcapture"
	];

	int main(string[] args) {

		int level = 1;
		int rounds = 1;
		if(args.length >= 2) {
			level = parse!int(args[1]);
		}
		if(args.length >= 3) {
			rounds = parse!int(args[2]);
		}

		foreach( i; (level-1)*rounds..level*rounds) {
			GC.collect();
			GC.minimize();

			try {
				testStore(new QuartFilterStore!()(), i/rounds, "8-bit Bloomier Filter");
			} catch ( Throwable e) {
				writeln(e);
			}

			GC.collect();
			GC.minimize();

			try {
				testStore(new QuartMapStore(), i/rounds, "8-bit Hashmap");
			}  catch ( Throwable e) {
				writeln(e);
			}

			GC.collect();
			GC.minimize();

			try {
				testStore(new FilterStore!()(), i/rounds, "32-bit Bloomier Filter");
			} catch ( Throwable e) {
				writeln(e);
			}

			GC.collect();
			GC.minimize();

			try {
				testStore(new MapStore(), i/rounds, "32-bit Hashmap");
			} catch ( Throwable e) {
				writeln(e);
			}
		}

		return 0;
	}


void testStore(NgramStore store, int level, string name) {
	writefln("\n\n%d ngram test: %s", cast(ulong)ngramAmounts[level], name);

	StopWatch timer;
	timer.start();

	store.populate(ngramFiles[level]);
	timer.stop();

	writefln("%s seconds", timer.peek().to!("seconds", float));
	ulong bytes = store.getTotalSize();
	writefln("Using %s bytes", bytes);
	writefln("Using %s MB", bytes/1_000_000.0);
	writefln("Using %s bytes/ngram", (bytes/ngramAmounts[level]));

	timer.reset();
	uint value;
	bool stored;

	uint qmask;
	if( level < 5 ) {
		qmask = 0b11;
	} else {
		qmask = 0b111;
	}
	int num_queries = 10_000_000;

	timer.start();
	foreach( i; 0..num_queries ) {
		stored = store.boolGet(queries[i & qmask], value);
	}

	timer.stop();
	float seconds = timer.peek().to!("seconds", float);
	writefln("%s seconds", seconds);
	writefln("%s reads/second", num_queries/seconds);
}
