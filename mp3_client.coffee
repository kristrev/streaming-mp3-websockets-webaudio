#Client side of the MP3 streaming server example, using websockets and webaudio
#API. Currently only tested on Chrome and iOS6. 
#
#Written by Kristian Evensen <kristian.evensen@gmail.com>

#Insert server IP!
client = new BinaryClient 'ws://<insert server ip>:9696'
context = new webkitAudioContext()
arr = []
nextStartTime = 0
numSegments = 0

connectionOpened = ->
    console.log "Established connection to server"

streamStarted = (stream, meta) ->
    stream.on 'data', streamData
    stream.on 'end', streamDone
    console.log "Stream of frames started"

streamData = (data) ->
    #I know that the only data I receive is mp3 frames, so it is safe to just
    #call decode on the data
    context.decodeAudioData data, playAudio, decodeError

decodeError = ->
    console.log "Decoding failed"

streamDone = ->
    console.log "Received all MP3 fragments from server"

playAudio = (buffer) ->
    #console.log "Decoding successful"
    #console.log buffer.duration

    #Create the source buffer, connect it to the final destination and tell it
    #when to start playing. Look at
    #http://www.html5rocks.com/en/tutorials/webaudio/intro/ for fun things to do
    #with the WebAudio API
    source = context.createBufferSource()
    source.buffer = buffer
    source.connect context.destination
    source.start nextStartTime

    #An attempt at scheduling mp3 frames correctly. It works, but the quality is
    #currently not great. I am not sure if this is a problem with this
    #algorithm, or WebAudio API itself and transition between frames. For
    #example, all the timers have second granularity.
    if nextStartTime == 0
        nextStartTime = context.currentTime
    else 
        nextStartTime = nextStartTime + buffer.duration

client.on 'open', connectionOpened
client.on 'stream', streamStarted
