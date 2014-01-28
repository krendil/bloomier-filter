module bloomier.stack;

import std.array;
import std.range;
debug import std.stdio;

struct Stack(T) {
private:
	T[] data;
	size_t top = 0;		

public:
	void push(T e) {
		debug if(top >= data.length) writefln("Tried to push to %s out of %s", top, data.length);
		data[top++] = e;
	}

	T pop() {
		return data[--top];
	}

	auto opSlice() {
		return data[0..top].retro;
	}
	
	@property
	bool empty() {
		return top == 0;
	}

	@property
	size_t length() {
		return top;
	}

	void clear() {
		top = 0;
	}

	@property
	size_t capacity() {
		return data.length;
	}

	@property
	void capacity(size_t value) {
		data.length = value;
	}
}
