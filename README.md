streaming-mp3-websockets-webaudio
=================================

Just because something is not designed for it, does not mean that it should be
done. This is an example of how to stream MP3 files to a browser using
WebSockets, and then playing them back using the WebAudio API. The server
only supports one active client and can only server one file (provided at start
as a command line argument). Also, the server assumes that the mp3 file
constains and ID3v2.3 tag, without an extension header.

The server is written for nodejs and requires binaryjs. The client uses the
webkit WebAudio-implementation, and has only been tested in Chrome and iOS6.
Both client and server are written in CoffeeScript, so that is required in order
to "compile".

If it had not been for one (current?) issue, this would have been a great
alternative for audio streaming. Currently, the playback is a bit choppy, which
I am unsure how to fix. The MP3 frame scheduling algorithm, which uses the
continously updated context.currentTime, should be able to schedule frames
directly after one another. However, for example, the timers in WebAudio all
have a resolution of a second, which might not provide enough granularity.

Suggestions, improvements and comments are more than welcome.

How to install and run
----------------------

1. Compile server and client using coffeescript. For example, 
    
   `coffee -c mp3_reader.coffee && coffee -c mp3_client.coffee`

2. Start the server, provide an mp3 file as the first command line argument. For
   example,
   
   `nodejs mp3_reader.js test.mp3`

3. Open webaudio-test.html. Make sure that mp3\_client.js is in the same folder.
