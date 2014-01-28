module ngramstore;

interface NgramStore {

	void populate(string filename);

	bool boolGet(string key, out uint value);

	uint exceptionGet(string key);

	ulong getTotalSize();
}
