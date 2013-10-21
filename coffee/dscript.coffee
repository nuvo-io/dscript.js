# dscript is a CoffeeScript API for DDS. This API allows web-app to share data in real-time among themselves
# and with native DDS applications.

root = this

dds = {}

if (typeof exports isnt 'undefined')
  if (typeof module isnt 'undefined' and module.exports)
    exports = module.exports = dds
  exports.dds = dds
else
  root.dds = dds

dds.VERSION = "0.1.0"

# `Option` monad implementation.
None = {}
None.map = (f) -> None
None.flatMap = (f) -> None
None.get = () -> undefined
None.getOrElse = (f) -> f()
None.orElse = (f) -> f()
None.isEmpty = () -> true

class Some
  constructor: (@value) ->
  map: (f)  -> new Some(f(@value))
  flatMap: (f) -> f(@value)
  get: () -> @value
  getOrElse: (f) -> @value
  orElse: (f) -> this
  isEmpty: () -> false


class Fail
  constructor: (@what) ->
  map: (f)  -> throw @what
  flatMap: (f) -> throw @what
  get: () -> throw @what
  getOrElse: (f) -> throw @what
  orElse: (f) -> throw @what
  isEmpty: () -> throw @what

# `Try` monad implementation.
class Success
  constructor: (@value) ->
  map: (f) -> f(@value)
  get: () -> @value
  getOrElse: (f) -> @value
  orElse: (f) -> this
  isFailure: () -> false
  isSuccess: () -> true
  toOption: () -> new Some(@value)
  recover: (f) -> this

class Failure
  constructor: (@exception) ->
  map: (f) -> None
  get: () -> @exception
  getOrElse: (f) -> f()
  orElse: (f) -> f()
  isFailure: () -> true
  isSuccess: () -> false
  toOption: () -> None
  recover: (f) -> f(@exception)

class Topic
  constructor: (@did, @tname, @ttype) ->


# A `DataReader` allows to read data for a given topic with a specific QoS.
# A `DataReader` goes through different states, it is intially disconnected and changes to the connected
# state when the underlying transport connection is successfully established with the server.
# At this point a `DataReader` can be explicitely closed or disconnected. A disconnection can happen
# as the result of a network failure or server failure. Disconnection and reconnections are managed by the
# runtime.
class DataReader
  constructor: (@runtime, @topic, @qos) ->
    @handlers = []
    @runtime.openDataReaderConnection(topic, qos, this)
    @onclose = () ->
    @closed = false
    @onconnect = () ->
    @ondisconnect = () ->
    @connected = false
    @eid = @runtime.generateEntityId()


  ## Attaches a listener to this data reader
  addListener: (l) ->
    idx = @handlers.length
    @handlers = @handlers.concat(l)
    idx

  removeListener: (idx) =>
    h = @handlers
    @handlers = h.slice(0, idx).concat(h.slice(idx+1, h.length))

  onDataAvailable: (m) =>
    s = m.data
    d = JSON.parse(s)
    @handlers.forEach((h) -> h(d))

  close: () =>
    console.log("Closing DR #{this}")
    @closed = true
    @runtime.closeDataReaderConnection(this)
    @onclose()


# A `DataWriter` allows to read data for a given topic with a specific QoS.
# A `DataWriter` goes through different states, it is intially disconnected and changes to the connected
# state when the underlying transport connection is successfully established with the server.
# At this point a `DataWriter` can be explicitely closed or disconnected. A disconnection can happen
# as the result of a network failure or server failure. Disconnection and reconnections are managed by the
# runtime.
class DataWriter
  constructor: (@runtime, @topic, @qos) ->
    @socket = dds.None
    @runtime.openDataWriterConnection(topic, qos, this)
    @onclose = () ->
    @closed = false
    @onconnect = () ->
    @ondisconnect = () ->
    @connected = false
    @eid = @runtime.generateEntityId()


  write: (ds...) ->
    @socket.map (
      (s) ->
        sendData = (x) ->
          xs = if (typeof(x) == 'string') then x else JSON.stringify(x)
          try
            s.send(xs)
          catch e
            console.log("Exception while sending data #{e}")

        ds.forEach(sendData)
    )

  close: () ->
    @closed = true
    @socket = new Fail("Invalid State Exception: Can't write on a closed DataWriter")
    @runtime.closeDataWriterConnection(this)
    @onclose()

class DataCache
  constructor: (@depth, @cache) -> if (@cache? == false) then @cache = {}

  write: (k, data) ->
    v = @cache[k]
    if (v? == false) then v = [data] else v = if (v.length < @depth) then v.concat(data) else v.slice(1, v.lenght).concat(data)
    @cache[k] = v

  forEach: (f) ->
    for k, v of @cache
      v.forEach(f)

  map: (f) ->
    result = {}
    for k, v of @cache
      result[k] = v.map(f)
    new DataCache(@depth, result)

  filter: (f) ->
    result = {}
    for k, v of @cache
      rv = fv for fv in v when f(v)
      result[k] = rv if rv.length isnt 0
    result

  filterNot: (f) -> filter((s) -> not f(s))

  read: () ->
    result = []
    for k, v of @cache
      result = result.concat(v)
    result

  take: () ->
    tmpCache = @cache
    @cache = []
    result = []
    for k, v of tmpCache
      result = result.concat(v)
    result

  takeWithFilter: (f) ->
    result = []
    for k, v of @cache
      tv = e for e in v when f(e)
      rv = e for e in v when not f(e)
      result = result.concat(tv)
      @cache[k] = rv
    result

  get: (k) ->
    v = @cache[k]
    if (v == undefined) None else new Some(v)

  getOrElse: (k, f) ->
    v = @cache[k]
    if (v == undefined) f() else new Some(v)

  fold: (z) => (f) =>
    r = z
    for k, v of @cache
      r = r + v.reduceRight(f)
    r

  clear: () =>
    @cache = {}


## Binds a reader to a cache
root.dds.bind = (key) -> (reader, cache) ->
  reader.addListener((d) -> cache.write(key(d), d))


root.dds.Topic = Topic
root.dds.DataReader = DataReader
root.dds.DataWriter = DataWriter
root.dds.DataCache = DataCache
root.dds.None = None
root.dds.Some = Some
root.dds.Success = Success
root.dds.Failure = Failure

###
  Protocol
###

DSEntityKind =
  Topic: 0
  DataReader: 1
  DataWriter: 2

DSCommandId =
  OK: 0
  Error: 1
  Create: 2
  Delegate: 3
  Unregister: 4


createHeader = (c, k, s) ->
  h =
    cid: c
    ek: k
    sn: s
  h

createTopicInfo = (domainId, topic, qos) ->
  ti =
    did: domainId
    tn:  topic.tname
    tt: topic.ttype
    qos: qos.policies
  ti

createCommand = (cmdId, kind) -> (seqn, topic, qos) ->
  th = createHeader(cmdId, kind, seqn)
  tb = createTopicInfo(topic.did, topic, qos)
  cmd =
    h: th
    b: tb
  cmd


root.dds.DSEntityKind = DSEntityKind
root.dds.DSCommandId = DSCommandId
root.dds.createDataReaderCommand = createCommand(DSCommandId.Create, DSEntityKind.DataReader)
root.dds.createDataWriterCommand = createCommand(DSCommandId.Create, DSEntityKind.DataWriter)

###
  QoS Policies
###

PolicyId =
  History:            0
  Reliability:        1
  Partition:          2
  ContentFilter:      3
  TimeFilter:         4
  Durability:         5
  TransportPriority:  6
  Ownership:          7
  OwnershipStrenght:  8


###
   History Policy
###
HistoryKind =
  KeepAll: 0
  KeepLast: 1

History =
  KeepAll:
    id: PolicyId.History
    k: HistoryKind.KeepAll

  KeepLast: (depth) ->
    result =
      id: PolicyId.History
      k: HistoryKind.KeepLast
      v: depth
    result


###
  Reliability Policy
###

ReliabilityKind =
  Reliable: 0
  BestEffort: 1

Reliability =
  BestEffort:
    id: PolicyId.Reliability
    k: ReliabilityKind.BestEffort

  Reliable:
    id: PolicyId.Reliability
    k: ReliabilityKind.Reliable

###
  Partition Policy
###
Partition = (p, plist...) ->
  policy =
    id: PolicyId.Partition
    vs: plist.concat(p)
  policy

###
  Content Filter Policy
###
ContentFilter = (expr) ->
  contentFilter =
    id: PolicyId.ContentFilter
    v: expr
  contentFilter

###
  Time Filter Policy
###
TimeFilter = (duration) ->
  timeFilter =
    id: PolicyId.TimeFilter
    v: duration
  timeFilter

###
  Durability Policy
###
DurabilityKind =
  Volatile: 0
  TransientLocal: 1
  Transient: 2
  Persistent: 3

Durability =
  Volatile:
    id: DurabilityKind.Volatile
  TransientLocal:
    id: DurabilityKind.TransientLocal
  Transient:
    id: DurabilityKind.Transient
  Persistent:
    id: DurabilityKind.Persistent

###
  The Entity QoS is represented as a list of Poilicies.
###
class EntityQos
  constructor: (p, ps...) ->
    console.log(p)
    console.log(ps)
    @policies =  ps.concat(p)
    console.log(@policies)

  add: (p...) -> new EntityQos(@policies.concat(p))



###
  Policy and QoS Exports
###

root.dds.HistoryKind = HistoryKind
root.dds.History = History
root.dds.ReliabilityKind = ReliabilityKind
root.dds.Reliability = Reliability
root.dds.Partition = Partition
root.dds.DurabilityKind = DurabilityKind
root.dds.Durability = Durability
root.dds.TimeFilter = TimeFilter
root.dds.ContentFilter = ContentFilter

root.dds.DataReaderQos = EntityQos
root.dds.DataWriterQos = EntityQos


# Resource paths
controllerPath = '/dscript/controller'
readerPrefixPath = '/dscript/reader'
writerPrefixPath = '/dscript/writer'

controllerURL = (dscriptServer) ->   dscriptServer + controllerPath
readerPrefixURL = (dscriptServer) ->  dscriptServer + readerPrefixPath
writerPrefixURL = (dscriptServer) ->  dscriptServer + writerPrefixPath

# The `Runtime` maintains the connection with the server, re-establish the connection if dropped and mediates
# the `DataReader` and `DataWriter` communication.
class Runtime
  # Creates a new DDS runtime
  constructor: (@server) ->
    @sn = 0
    @drmap = {}
    @dwmap = {}
    @drconnections = {}
    @dwconnections = {}
    @onclose = (evt) ->
    @onconnect = () ->
    @ondisconnect = (evt) ->
    @connected = false
    @closed = true
    @eidCount = 0


  generateEntityId: () ->
    id = @eidCount
    @eidCount += 1
    id

  # Establish a connection with the dscript.play server
  connect: () =>
    if @connected is false
      url = controllerURL(@server)
      console.log("Connecting to: #{url}")
      @ctrlSock = None
      @webSocket = new WebSocket(url)
      @pendingCtrlSock = new Some(@webSocket)

      @pendingCtrlSock.map (
        (s) =>
          s.onopen = () =>
            console.log('Connected to: ' + @server)
            @ctrlSock = @pendingCtrlSock
            @connected = true
            # We may need to re-establish dropped data connection, if this connection is following
            # a disconnection.
            console.log("Re-establishing dropped connection -- if needed")
            @establishDroppedDataConnections()
            @onconnect()
      )

      @pendingCtrlSock.map (
        (s) => s.onclose =
          (evt) =>
            console.log("The  #{@server} seems to have dropped the connection.")
            @connected = false
            @closed = false
            @ctrlSock = None
            @ondisconnect(evt)
      )


      @pendingCtrlSock.map (
        (s) =>
          s.onmessage = (msg) =>
            this.handleMessage(msg)
      )
    else
      console.log("Warning: Trying to connect an already connected Runtime")

  # Re-establish connections that had been dropped due to a temporary network connectivity loss
  # or a server failure.
  establishDroppedDataConnections: () =>
    for k, v of @drconnections
      if v.sock.readyState is v.sock.CLOSED
        console.log("Establishing dropped connection for data-reader")
        @openDataReaderConnection(v.dr.topic, v.dr.qos, v.dr)

    for k, v of @dwconnections
      if v.sock.readyState is v.sock.CLOSED
        console.log("Establishing dropped connection for data-writer")
        @openDataWriterConnection(v.dw.topic, v.dw.qos, v.dw)


  # Disconnects, withouth closing, a `Runtime`. Notice that there is a big difference between disconnecting and
  # closing a `Runtime`. The a disconnected `Runtime` can be reconnected and retains state across
  # connection/disconnections. On the other hand, once closed a `Runtime` clears up all current state.
  disconnect: () =>
    @connected = false
    @ctrlSock.map(
      (s) -> s.close()
    )

    for k, v of @drconnections
      v.sock.close() # the onclose will call the ondisconnect

    for k, v of @dwconnections
      v.sock.close() # the onclose will call the ondisconnect

    @ondisconnect()


  # Close the DDS runtime and as a consequence all the `DataReaders` and `DataWriters` that belong to this runtime.
  close: () =>
    @ctrlSock.map (
      (s) =>
        s.close()
        this.onclose()
    )
    for k, v of @drconnections
      v.dr.close()


    for k, v of @dwconnections
      v.dw.close()


  isConnected: () => @connected

  isClosed: () => @closed


  openDataReaderConnection: (topic, qos, dr) =>
    cmd = dds.createDataReaderCommand(@sn, topic, qos)
    @drmap[@sn] = dr
    @sn = @sn + 1
    scmd = JSON.stringify(cmd)
    @ctrlSock.map((s) -> s.send(scmd))

  closeDataReaderConnection: (dr) =>
    {dr, sock} = @drconnections[dr.eid]
    if (sock isnt undefined)
      sock.close()
      delete @drconnections[dr.eid]

  closeDataWriterConnection: (dw) =>
    {dw, sock} = @dwconnections[dw.eid]
    if (sock isnt undefined)
      sock.close()
      delete @dwconnections[dw.eid]


  openDataWriterConnection: (topic, qos, dw) =>
    cmd = dds.createDataWriterCommand(@sn, topic, qos)
    @dwmap[@sn] = dw
    @sn = @sn + 1
    scmd = JSON.stringify(cmd)
    console.log("Creating Data Writer on #{@ctrlSock.get()}")
    @ctrlSock.map((s) -> s.send(scmd))
    console.log("Command sent: #{cmd}")

  handleMessage: (s) =>
    console.log('received'+ s.data)
    msg = JSON.parse(s.data)
    if (msg.h.cid == DSCommandId.OK)
      if (msg.h.ek == DSEntityKind.DataReader)
        eid = msg.b.eid
        url = readerPrefixURL(@server) + '/' + eid
        dr = @drmap[msg.h.sn]
        drsock = new WebSocket(url)
        drsock.onmessage = dr.onDataAvailable

        drsock.onclose = (evt) ->
          dr.connected = false
          dr.ondisconnect(evt)

        delete @drmap[msg.h.sn]
        drc = dr: dr, sock: drsock
        @drconnections[dr.eid] = drc
        dr.connected = true
        dr.onconnect()

      else if (msg.h.ek == DSEntityKind.DataWriter)
        eid = msg.b.eid
        url = writerPrefixURL(@server) + '/' + eid
        dw = @dwmap[msg.h.sn]
        dwsock = new WebSocket(url)

        dwsock.onclose = (evt) ->
          dw.socket = new dds.Failure(evt)
          dw.connected = false
          dw.ondisconnect(evt)


        dw.socket = new dds.Success(dwsock)
        delete @dwmap[msg.h.sn]
        dwc = dw: dw, sock: dwsock
        @dwconnections[dw.eid] = dwc
        dw.connected = true
        dw.onconnect()


    if (msg.h.cid == DSCommandId.Error)
      throw (msg.b.msg)




root.dds.Runtime = Runtime
