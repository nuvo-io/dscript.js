###
 This file defines the CoffeeScript API for DDS
###

root = this

dds = {}

if (typeof exports isnt 'undefined')
  if (typeof module isnt 'undefined' and module.exports)
    exports = module.exports = dds
  exports.dds = dds
else
  root.dds = dds

dds.VERSION = "0.1.0"

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

class Topic
  constructor: (@did, @tname, @ttype) ->

class DataReader
  constructor: (@topic, @qos) ->
    @handlers = []
    dds.ddscriptRuntime.createDataReaderConnection(topic, qos, this)

  ## Attaches a listener to this data reader
  addListener: (l) ->
    idx = @handlers.length
    @handlers = @handlers.concat(l)
    idx

  removeListener: (idx) ->
    h = @handlers
    @handlers = h.slice(0, idx).concat(h.slice(idx+1, h.length))

  socketDataHandler: (m) =>
    s = m.data
    d = JSON.parse(s)
    @handlers.forEach((h) -> h(d))

class DataWriter
  constructor: (@topic, @qos) ->
    @socket = dds.None
    dds.ddscriptRuntime.createDataWriterConnection(topic, qos, this)

  write: (ds...) ->
    @socket.map (
      (s) ->
        sendData = (x) ->
          xs = if (typeof(x) == 'string') then x else JSON.stringify(x)
          try
            s.send(xs)
          catch e
            console.log(e)

        ds.forEach(sendData)
    )


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

  takeWhile: (f) ->
    result = []
    for k, v of @cache
      tv = e for e in v when f(v)
      rv = e for e in v when not f(v)
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


## Binds a reader to a cache
root.dds.bind = (key) -> (reader, cache) ->
  reader.addListener((d) -> cache.write(key(d), d))

root.dds.bindWithFun = (key) -> (fun) -> (reader, cache) ->
  reader.addListener((d) ->
    fun(cache)
    cache.write(key(d), d))

root.dds.Topic = Topic
root.dds.DataReader = DataReader
root.dds.DataWriter = DataWriter
root.dds.DataCache = DataCache
root.dds.None = None
root.dds.Some = Some

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

###
  Runtime
###

class Runtime
  constructor: (@controllerURL, @readerURLPrefix, @writerURLPrefix) ->
    @sn = 0
    @drmap = {}
    @dwmap = {}

    console.log("Connecting to: #{@controllerURL}")
    @ctrlSock = new WebSocket(@controllerURL)
    @ctrlSock.onmessage = (msg) => this.handleMessage(msg)


  createDataReaderConnection: (topic, qos, dr) =>
    cmd = dds.createDataReaderCommand(@sn, topic, qos)
    @drmap[@sn] = dr
    @sn = @sn + 1
    scmd = JSON.stringify(cmd)
    @ctrlSock.send(scmd)

  createDataWriterConnection: (topic, qos, dw) =>
    cmd = dds.createDataWriterCommand(@sn, topic, qos)
    @dwmap[@sn] = dw
    @sn = @sn + 1
    scmd = JSON.stringify(cmd)
    @ctrlSock.send(scmd)


  handleMessage: (s) =>
    console.log('received'+ s.data)
    msg = JSON.parse(s.data)
    if (msg.h.cid == DSCommandId.OK)
      if (msg.h.ek == DSEntityKind.DataReader)
        eid = msg.b.eid
        url = @readerURLPrefix + '/' + eid
        dr = @drmap[msg.h.sn]
        drsock = new WebSocket(url)
        drsock.onmessage = dr.socketDataHandler
        delete @drmap[msg.h.sn]
      else if (msg.h.ek == DSEntityKind.DataWriter)
        eid = msg.b.eid
        url = @writerURLPrefix + '/' + eid
        dw = @dwmap[msg.h.sn]
        dwsock = new WebSocket(url)
        dw.socket = new dds.Some(dwsock)
        delete @dwmap[msg.h.sn]
    if (msg.h.cid == DSCommandId.Error)
      throw (msg.b.msg)

root.dds.ddscriptRuntime = new Runtime(dsconf.controllerURL, dsconf.readerPrefixURL, dsconf.writerPrefixURL)
root.dds.Runtime = Runtime
