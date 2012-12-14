#MP3 streaming server, for nodejs, which streams files over websockets. Requires binaryjs to
#work. At start, you have to provide the mp3 file to stream as the first command
#line argument. Assumes that an ID3v2 tag is present, without extension headers.
#
#Written by Kristian Evensen <kristian.evensen@gmail.com>

fs = require 'fs'
bs = require 'binaryjs'
BinaryServer = bs.BinaryServer
bss = null
curClient = null

#Used for the streaming
stream = null
mp3FragmentIdx = 0

#Experiment with this one, larger chunks tend to give better sound
numMp3Fragments = 20

#This should be the maximum
mp3Frames = []
lastFrameIdx = 0
first = true
syncWord = 0
numSegments = 0

#Tables with lookup information about mp3 files.
#These are all defined in the standard, copied from
#http://www.hydrogenaudio.org/forums/index.php?showtopic=85125
mpeg_bitrates = [
    #Version 2.5
    [
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], #Reserved
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0], #Layer 3
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0], #Layer 2
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0] #Layer 1
    ],
    #Reserved
    [
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    ],
    #Version 2
    [
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], #Reserved
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0], #Layer 3
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0], #Layer 2
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0] #Layer 1
    ],
    #Version 1
    [
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], #Reserved
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0], #Layer 3
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0], #Layer 2
        [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0] #Layer 1
    ]
]

#Sample rates - use [version][srate]
mpeg_srates = [
    [11025, 12000, 8000, 0], #MPEG 2.5
    [0, 0, 0, 0], #Reserved
    [22050, 24000, 16000, 0], #MPEG 2
    [44100, 48000, 32000, 0] #MPEG 1
]

#Samples per frame - use [version][layer]
mpeg_frame_samples = [
#    Rsvd     3     2     1  < Layer  v Version
    [0, 576, 1152, 384], #2.5
    [0, 0, 0, 0], #Reserved
    [0, 576, 1152, 384], #2
    [0, 1152, 1152, 384] #1
]

#Slot size (MPEG unit of measurement) - use [layer]
mpeg_slot_size = [0, 1, 1, 4] #Rsvd, 3, 2, 1

class Mp3Frame
    constructor: (length) ->
        @mp3FrameBuf = new Buffer length
        @mp3FrameLength = length

startServer = ->
    bss = new BinaryServer {port: 9696}
    bss.on 'connection', clientConnected

mergeAndSendFrames = ->
    sizeBuffer = 0
    limit = mp3FragmentIdx + numMp3Fragments

    if limit > mp3Frames.length
        limit = mp3Frames.length

    #Find the size of the merged buffer (buffer that will be sent to client)
    for i in [mp3FragmentIdx...limit]
        sizeBuffer += mp3Frames[i].mp3FrameLength

    mergedBuffer = new Buffer sizeBuffer
    mergedBufferIdx = 0

    #Fill the buffer with the correct fragments
    for i in [mp3FragmentIdx...limit]
        mp3Frames[i].mp3FrameBuf.copy mergedBuffer, mergedBufferIdx, 0
        mergedBufferIdx += mp3Frames[i].mp3FrameLength

    mp3FragmentIdx = limit

    if sizeBuffer > 0
        stream.write mergedBuffer

    return sizeBuffer

clientConnected = (client) ->
    if curClient != null
        curClient.close()

    curClient = client
    console.log "Client connected, will send first mp3 frame"
    stream = client.createStream()
    stream.on 'drain', streamDrained
    mergeAndSendFrames()

#Triggered every time the underlaying socket has drained, i.e., the previous
#buffer has been sent
streamDrained = ->
    if mergeAndSendFrames() == 0
        console.log "Sent", mp3FragmentIdx, "frames"
        mp3FragmentIdx = 0

        #Remove the listener and notify the server that we are done
        stream.removeListener 'drain', streamDrained
        stream.end()

parseMp3File = (err, data) ->
    numFrames = 0

    #Assumes ID3v2.3
    #Conversion from the unsynchronus integer, which is BE
    header_size = (data[9] & 0x7f | ((data[8] & 0x7f) << 7) | ((data[7] & 0x7f) <<
    14) | ((data[6] & 0x7f) << 21))

    #Offset from the header, point at first byte
    headerIdx = header_size + 10

    console.log "Header size", header_size
    frameSum = 0

    while headerIdx < data.length
        #Within bounds and first part of sync word seen
        if headerIdx + 1 < data.length && data[headerIdx] == 0xFF
            syncWord = (data[headerIdx] << 8) | data[headerIdx+1]

            if syncWord == 0xFFFB or syncWord == 0xFFFA
                #Parse MP3 header
                ver = (data[headerIdx+1] & 0x18) >> 3
                lyr = (data[headerIdx+1] & 0x06) >> 1
                pad = (data[headerIdx+2] & 0x02) >> 1
                brx = (data[headerIdx+2] & 0xf0) >> 4
                srx = (data[headerIdx+2] & 0x0c) >> 2

                bitrate = mpeg_bitrates[ver][lyr][brx] * 1000
                samprate = mpeg_srates[ver][srx]
                samples = mpeg_frame_samples[ver][lyr]
                slot_size = if pad == 1 then mpeg_slot_size[lyr] else 0
      
                console.log "Version", ver
                console.log "Layer", lyr
                console.log "Bitrate", bitrate
                console.log "Frequency", samprate
                console.log "Samples", samples
                console.log "Padding", pad
                console.log "Slot size", slot_size
                console.log "Header idx", headerIdx

                #Formula for calculating mp3 lenth (in bytes):
                # Samples is the number of samples contained in this frame
                # Frequency is the frequency of the samples
                # To get the length of each frame, do samples/freq
                # To get the length in bytes, do (bitrate / 8) * length in time
                time_length = samples / samprate
                fsize = Math.floor (((bitrate / 8) * time_length) + slot_size)

                #Create the mp3 frame
                frame = new Mp3Frame(fsize)
                data.copy frame.mp3FrameBuf, 0, headerIdx, headerIdx+fsize
                mp3Frames.push(frame)

                numFrames++
                headerIdx += fsize
        else
            #If I hit the last TAG just break (i.e., there is no
            break

    console.log "File length", data.length
    console.log "HeaderIdx", headerIdx
    console.log "MP3 frames " + numFrames
    console.log "Will start streaming server"
    startServer()

fs.readFile process.argv[2], parseMp3File
