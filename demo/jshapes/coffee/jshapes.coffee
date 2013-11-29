###
  jshapes is a web implementation of the "shapes" application used
   by DDS vendors to demonstrate interoperability.  That said this
   simple application tries to show how DDS can be effectively used to
   stream and render real-time data in a web-browser.

   For information contact angelo@icorsaro.net
###

root = this

jshapes = {}

if (typeof exports isnt 'undefined')
  if (typeof module isnt 'undefined' and module.exports)
    exports = module.exports = jshapes
  exports.jshapes = jshapes
else
  root.jshapes = jshapes

dscriptServer = 'ws://54.229.92.216:9000'

runtime = new dds.Runtime(dscriptServer)

runtime.ondisconnect = (e) ->
  sb = root.document.getElementById("subscribeBtn")
  console.log("Enabling #{sb}")
  sb.disabled = true
  pb = root.document.getElementById("publishBtn")
  pb.disabled = true
  alert('Connection Failure! Please check your Internet connection')

runtime.onconnect = () ->
  sb = root.document.getElementById("subscribeBtn")
  sb.disabled = false
  pb = root.document.getElementById("publishBtn")
  pb.disabled = false
  cb = root.document.getElementById("connectBtn")
  cb.innerHTML = " Disconnect"
  cb.onclick = disconnect
  clrb = root.document.getElementById("clearTPSBtn")
  clrb.disabled = false


runtime.ondisconnect = () ->
  cb = root.document.getElementById("connectBtn")
  cb.innerHTML = " Connect"
  cb.onclick = connect

connect = () ->
  runtime.connect(dsconf.dscriptServer)

disconnect = () ->
  runtime.disconnect()


clearTopicPubSub = () ->
  sub = JShapesProperties.shapeTopic()
  switch sub
    when "Circle" then clearCircles()
    when "Square" then clearSquares()
    when "Triangle" then clearTriangles()


JShapesProperties =
  logo:
    img: new Image()
    coord:
      x: 280
      y: 300
  bounds:
    w: 501
    h: 361
  refresh: 40 # msec

  canvas: () -> root.document.getElementById("iShapeCanvas")
  g2d: () -> root.document.getElementById("iShapeCanvas").getContext("2d")
  shapeTopic: () -> root.document.getElementById("topicSelection").value.toString()
  shapeColor: () -> root.document.getElementById("colorSelection").value.toString()
  shapeSize: () -> parseInt(root.document.getElementById("topicSize").value.toString(), 10)
  shapeSpeedX: () -> parseInt(root.document.getElementById("topicSpeedX").value.toString(), 10)
  shapeSpeedY:  () -> parseInt(root.document.getElementById("topicSpeedY").value.toString(), 10)
  shapeHistory: () -> parseInt(root.document.getElementById("historyDepth").value, 10)
  shapeHistoryPolicy: () -> dds.History.KeepLast(parseInt(root.document.getElementById("historyDepth").value, 10))
  shapePartitionPolicy: () -> dds.Partition(root.document.getElementById("partition").value)
  shapeReliabilityPolicy: () ->
    kind = parseInt(root.document.getElementById("reliability").value.toString(), 10)
    if (kind == dds.ReliabilityKind.BestEffort) then dds.Reliability.BestEffort else dds.Reliability.Reliable

  shapeTimeFilter: () ->
    tfv = parseInt(root.document.getElementById("tfilter").value, 10)
    console.log("TimeFilter = #{tfv}")
    if (tfv == 0) then dds.None else new dds.Some(dds.TimeFilter(tfv))

  shapeContentFilter: () ->
    fv = root.document.getElementById("cfilter").value
    console.log("CFilter = #{fv}")
    if (fv.length == 0) then dds.None else new dds.Some(dds.ContentFilter(fv))



  shapeReaderQos: () ->
    baseqos = new dds.DataReaderQos(
      JShapesProperties.shapeReliabilityPolicy(),
      JShapesProperties.shapePartitionPolicy(),
      JShapesProperties.shapeHistoryPolicy())

    cfp = JShapesProperties.shapeContentFilter()
    tfp = JShapesProperties.shapeTimeFilter()

    baseqos = if (cfp isnt dds.None) then baseqos.add(cfp.get()) else baseqos
    if (tfp isnt dds.None) then baseqos.add(tfp.get()) else baseqos


  shapeWriterQos: () ->
    new dds.DataWriterQos(
      JShapesProperties.shapeReliabilityPolicy(),
      JShapesProperties.shapePartitionPolicy(),
      JShapesProperties.shapeHistoryPolicy())

  defaultShapeSize: 60


JShapesProperties.logo.img.src = "./images/logo.png"


ShapeColor =
  red:      "RED"
  green:    "GREEN"
  blue:     "BLUE"
  orange:   "ORANGE"
  yellow:   "YELLOW"
  magenta:  "MAGENTA"
  cyan:     "CYAN"
  gray:     "GRAY"
  white:    "WHITE"
  black:    "BLACK"

colorMap = {}
colorMap[ShapeColor.red] = "#cc3333"
colorMap[ShapeColor.green] = "#99cc66"
colorMap[ShapeColor.blue] = "#336699"
colorMap[ShapeColor.orange] = "#ff9933"
colorMap[ShapeColor.yellow] = "#ffff66"
colorMap[ShapeColor.magenta] = "#cc99cc"
colorMap[ShapeColor.cyan] = "#99ccff"
colorMap[ShapeColor.gray] = "#666666"
colorMap[ShapeColor.white] = "#ffffff"
colorMap[ShapeColor.black] = "#000000"

drqos = new dds.DataReaderQos(dds.Reliability.Reliable)
dwqos = new dds.DataWriterQos(dds.Reliability.BestEffort)

circleTopic = new dds.Topic(0, 'Circle', 'org.omg.dds.demo.ShapeType')
squareTopic = new dds.Topic(0, 'Square', 'org.omg.dds.demo.ShapeType')
triangleTopic = new dds.Topic(0, 'Triangle', 'org.omg.dds.demo.ShapeType')

circleDR = null
squareDR = null
triangleDR = null

circleDW  = null
squareDW  = null
triangleDW = null

inCircleCache= dds.None
inSquareCache = dds.None
inTriangleCache = dds.None

outCircleCache= dds.None
outSquareCache = dds.None
outTriangleCache = dds.None

bindShape = dds.bind((s) -> s.color)

class Shape
  constructor: (@color, @shapesize, @x, @y, @dx, @dy) ->

randomShape = (color, size, dx, dy) ->
  s = new Shape()
  s.color = color
  s.shapesize = size
  s.x = Math.floor(Math.random()*JShapesProperties.bounds.w)
  s.y = Math.floor(Math.random()*JShapesProperties.bounds.h)
  s.dx = dx
  s.dy = dy
  s

stripShape = (s) ->
  ss = {}
  ss.color = s.color
  ss.x = s.x
  ss.y = s.y
  ss.shapesize = s.shapesize
  ss


drawCircle = (g2d, dotcolor) -> (s) ->
  g2d.fillStyle = colorMap[s.color]
  g2d.beginPath()
  g2d.arc(s.x, s.y, s.shapesize/2, 0, 2*Math.PI, true)
  g2d.fill()
  g2d.fillStyle = dotcolor
  g2d.beginPath()
  g2d.arc(s.x, s.y, s.shapesize/6, 0, 2*Math.PI, true)
  g2d.closePath()
  g2d.fill()


drawSquare = (g2d, dotcolor) -> (s) ->
  g2d.fillStyle = colorMap[s.color]
  g2d.fillRect(s.x, s.y, s.shapesize, s.shapesize)

  g2d.fillStyle = dotcolor
  scaledw = s.shapesize/3
  x0 = s.x + scaledw
  y0 = s.y + scaledw
  g2d.fillRect(x0, y0, scaledw, scaledw)



drawTriangleShape = (g2d, a, m) ->
  g2d.beginPath()
  g2d.moveTo(0,0)
  g2d.lineTo(a, 0)
  g2d.lineTo(a-m, -a)
  g2d.closePath()


drawTriangle = (g2d, dotcolor) -> (s) ->
  g2d.save()
  x0 = s.x
  y0 = s.y + s.shapesize
  g2d.translate(x0, y0)
  g2d.fillStyle = colorMap[s.color]
  a = s.shapesize
  m = s.shapesize/2
  drawTriangleShape(g2d, a, m)
  g2d.fill()
  g2d.restore()

  g2d.save()
  x0 = s.x + m
  y0 = s.y + 1.25*m
  g2d.fillStyle = dotcolor
  g2d.beginPath()
  g2d.arc(x0, y0, s.shapesize/6, 0, 2*Math.PI, true)
  g2d.closePath()
  g2d.fill()
  g2d.restore()

###
   Bounding box for different shapes
###
circleBBox = (s) ->
  r = s.shapesize/2
  bbox = {}
  bbox.x = s.x - r
  bbox.y = s.y - r
  bbox.w = bbox.h = s.shapesize
  bbox

squareBBox = (s) ->
  bbox = {}
  bbox.x = s.x
  bbox.y = s.y
  bbox.w = bbox.h = s.shapesize
  bbox

triangleBBox = squareBBox

###
  Dynamics
    bbox -> gives the bounding for the given shape
    bounds -> the bounds within which the shape has to bounce
    dx, dy -> speed in x, y direction
###
bouncingDynamic = (bbox, bounds) -> (s) ->
  box = bbox(s)
  dx = s.dx
  dy = s.dy


  if (box.x + box.w > bounds.w)
    dx = -dx if dx > 0
    if (Math.random() > 0.5)
      dy = -dy

    x = bounds.w  - box.w

  else if(box.y + box.h > bounds.h)
    dy = -dy if dy > 0

    if (Math.random() > 0.5)
      dx = -dx

    y = bounds.h - box.h

  else if (box.x <= 0)
    dx = -dx if dx < 0
    if (Math.random() > 0.5)
      dy = -dy


  else if (box.y <= 0)
    dy = -dy if dy < 0
    if (Math.random() > 0.5)
      dx = -dx

  s.x = s.x + dx
  s.y = s.y + dy
  s.dx = dx
  s.dy = dy
  s

bouncingCircles = bouncingDynamic(circleBBox, JShapesProperties.bounds)
bouncingSquares = bouncingDynamic(squareBBox, JShapesProperties.bounds)
bouncingTriangles = bouncingDynamic(triangleBBox, JShapesProperties.bounds)

animate = () =>
  g2d = JShapesProperties.g2d()
  g2d.fillStyle = colorMap[ShapeColor.white]
  g2d.fillRect(0,0,JShapesProperties.bounds.w, JShapesProperties.bounds.h)

  g2d.drawImage(JShapesProperties.logo.img, JShapesProperties.logo.coord.x, JShapesProperties.logo.coord.y)

  whiteSpotCircle = drawCircle(g2d, colorMap[ShapeColor.white])
  blackSpotCirlce = drawCircle(g2d, colorMap[ShapeColor.black])

  whiteSpotSquare = drawSquare(g2d, colorMap[ShapeColor.white])
  blackSpotSquare = drawSquare(g2d, colorMap[ShapeColor.black])

  whiteSpotTriangle = drawTriangle(g2d, colorMap[ShapeColor.white])
  blackSpotTriangle = drawTriangle(g2d, colorMap[ShapeColor.black])

  outCircleCache.map((c) -> c.forEach(whiteSpotCircle))
  outSquareCache.map((c) -> c.forEach(whiteSpotSquare))
  outTriangleCache.map((c) -> c.forEach(whiteSpotTriangle))

  inCircleCache.map((c) -> c.forEach(blackSpotCirlce))
  inSquareCache.map((c) -> c.forEach(blackSpotSquare))
  inTriangleCache.map((c) -> c.forEach(blackSpotTriangle))

  outCircleCache = outCircleCache.map((c) -> c.map(bouncingCircles))
  outSquareCache = outSquareCache.map((c) -> c.map(bouncingSquares))
  outTriangleCache = outTriangleCache.map((c) -> c.map(bouncingTriangles))

  outCircleCache.map((c) -> c.forEach((s) -> circleDW.write(stripShape(s))))
  outSquareCache.map((c) -> c.forEach((s) -> squareDW.write(stripShape(s))))
  outTriangleCache.map((c) -> c.forEach((s) -> triangleDW.write(stripShape(s))))


publishTopic = () ->
  ts = JShapesProperties.shapeTopic()
  color =JShapesProperties.shapeColor()
  size = 2*JShapesProperties.shapeSize()
  dx = JShapesProperties.shapeSpeedX()
  dy = JShapesProperties.shapeSpeedY()
  shape = randomShape(color, size, dx, dy)
  dwQos = JShapesProperties.shapeWriterQos()

  if (ts == 'Circle')
    if (circleDW is null)
      circleDW  = new dds.DataWriter(runtime, circleTopic, dwQos)
      outCircleCache = new dds.Some(new dds.DataCache(1))
    outCircleCache.map((c) -> c.write(color, shape))


  else if (ts == 'Square')
    if (squareDW is null)
      squareDW  = new dds.DataWriter(runtime, squareTopic, dwQos)
      outSquareCache = new dds.Some(new dds.DataCache(1))
    outSquareCache.map((c) -> c.write(color, shape))

  else if (ts == "Triangle")
    if (triangleDW is null)
      triangleDW = new dds.DataWriter(runtime, triangleTopic, dwQos)
      outTriangleCache = new dds.Some(new dds.DataCache(1))
    outTriangleCache.map((c) -> c.write(color, shape))


subscribeTopic = () ->
  ts = JShapesProperties.shapeTopic()
  drQos = JShapesProperties.shapeReaderQos()
  history = JShapesProperties.shapeHistory()

  if (ts == "Circle" and circleDR is null)
    circleDR = new dds.DataReader(runtime, circleTopic, drQos)
    inCircleCache = new dds.Some(new dds.DataCache(history))
    inCircleCache.map((c) -> bindShape(circleDR, c))


  else if (ts == "Square" and squareDR is null)
    squareDR = new dds.DataReader(runtime, squareTopic, drQos)
    inSquareCache = new dds.Some(new dds.DataCache(history))
    inSquareCache.map((c) -> bindShape(squareDR, c))


  else if (ts == "Triangle" and triangleDR is null)
    triangleDR = new dds.DataReader(runtime, triangleTopic, drQos)
    inTriangleCache = new dds.Some(new dds.DataCache(history))
    inTriangleCache.map((c) -> bindShape(triangleDR, c))


runJShapes = () ->
  setInterval("animate()", JShapesProperties.refresh)


clearPS = (r, rc, w, wc) ->
  if r isnt null
    r.close()
  if w isnt null
    w.close()
  rc = dds.None
  wc = dds.None

clearCircles = () ->
  clearPS(circleDR, inCircleCache, circleDW, outCircleCache)
  circleDR = circleDW  = null
  inCircleCache = outCircleCache = dds.None

clearSquares = () ->
  clearPS(squareDR, inSquareCache, squareDW, outSquareCache)
  squareDR = squareDW = null
  inSquareCache = outSquareCache = dds.None

clearTriangles = () ->
  clearPS(triangleDR, inTriangleCache, squareDW, outTriangleCache)
  triangleDR = triangleDW = null
  inTriangleCache = outTriangleCache = dds.None

this.animate = animate
this.runJShapes = runJShapes
this.publishTopic = publishTopic
this.subscribeTopic = subscribeTopic
this.connect = connect
this.disconnect = disconnect
this.clearTopicPubSub = clearTopicPubSub
this.window.onload = () -> runJShapes()

