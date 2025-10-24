/*

MIT License

Copyright (c) 2025, Steinberg Media Technologies GmbH, All rights reserved.
Copyright (c) 2025, Guillaume Piolat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following condition.s:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/
module dplug.vst3.ibstream;

version(VST3):

import dplug.vst3.ftypes;

/** Base class for streams.
\ingroup pluginBase
- read/write binary data from/to stream
- get/set stream read-write position (read and write position is the same)
*/
interface IBStream: FUnknown
{
public:
nothrow:
@nogc:

    alias IStreamSeekMode = int;
	enum : IStreamSeekMode
	{
		kIBSeekSet = 0, ///< set absolute seek position
		kIBSeekCur,     ///< set seek position relative to current position
		kIBSeekEnd      ///< set seek position relative to stream end
	}

	/** Reads binary data from stream.
	\param buffer : destination buffer
	\param numBytes : amount of bytes to be read
	\param numBytesRead : result - how many bytes have been read from stream (set to 0 if this is of no interest) */
	tresult read (void* buffer, int32 numBytes, int32* numBytesRead = null);
	
	/** Writes binary data to stream.
	\param buffer : source buffer
	\param numBytes : amount of bytes to write
	\param numBytesWritten : result - how many bytes have been written to stream (set to 0 if this is of no interest) */
	tresult write (void* buffer, int32 numBytes, int32* numBytesWritten = null);
	
	/** Sets stream read-write position. 
	\param pos : new stream position (dependent on mode)
	\param mode : value of enum IStreamSeekMode
	\param result : new seek position (set to 0 if this is of no interest) */
	tresult seek (int64 pos, int32 mode, int64* result = null);
	
	/** Gets current stream read-write position. 
	\param pos : is assigned the current position if function succeeds */
	tresult tell (int64* pos);

    __gshared immutable TUID iid = INLINE_UID(0xC3BF6EA2, 0x30994752, 0x9B6BF990, 0x1EE33E9B);
}

/+
/** Stream with a size. 
\ingroup pluginBase
[extends IBStream] when stream type supports it (like file and memory stream) */
class ISizeableStream: FUnknown
{
public:

	/** Return the stream size */
	virtual tresult PLUGIN_API getStreamSize (int64& size) = 0;
	/** Set the steam size. File streams can only be resized if they are write enabled. */
	virtual tresult PLUGIN_API setStreamSize (int64 size) = 0;


	static const FUID iid;
};
DECLARE_CLASS_IID (ISizeableStream, 0x04F9549E, 0xE02F4E6E, 0x87E86A87, 0x47F4E17F)

+/