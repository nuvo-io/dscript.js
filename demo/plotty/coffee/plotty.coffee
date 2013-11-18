root = this

plotty= {}

if (typeof exports isnt 'undefined')
  if (typeof module isnt 'undefined' and module.exports)
    exports = module.exports = jshapes
  exports.jshapes = jshapes
else
  root.plotty = plotty



drag = false


BEGIN = 0
CONTROL = 1
END = 2
STATUSES = 3
points = []
state = BEGIN

dscriptServer = "ws://192.168.0.38:9990"

class Point
  constructor: (@x, @y) ->

interpolate = (g2d, points, color) ->
  g2d.save()
  g2d.moveTo(points[BEGIN].x, points[BEGIN].y)
  g2d.quadraticCurveTo(points[CONTROL].x, points[CONTROL].y, points[END].x, points[END].y)
  g2d.strokeStyle = color
  g2d.lineWidth = 5
  g2d.stroke()
  g2d.restore()

root.color = ""
window.onload = () ->
  console.log("Running main")
  runtime = new dds.Runtime(dscriptServer)
  runtime.connect()
  plottyTopic = new dds.Topic(0, "QuadraticCurve", "io.nuvo.plotty.QuadraticCurve")

  runtime.onconnect = () ->
    root.writer = new dds.DataWriter(runtime, plottyTopic, new dds.DataWriterQos(dds.Reliability.Reliable))
    root.reader = new dds.DataReader(runtime, plottyTopic, new dds.DataReaderQos(dds.Reliability.Reliable))
    root.reader.addListener((d) -> interpolate(root.g2d, d.points, d.color))


  root.canvas = root.document.getElementById("plottyCanvas")
  console.log("canvas = #{canvas}")
  root.g2d = canvas.getContext("2d")


  canvas.onmousemove = (e) ->
    if (drag)
      points[state] = new Point(e.x, e.y)
      if (state == END)
        interpolate(root.g2d, points, root.color)
        curve = {}
        curve.cid = 0
        curve.color = root.color
        curve.points = points
        root.writer.write(curve)
        points[BEGIN] = points[END]
        state = CONTROL
      else
        state = state + 1


  canvas.onmousedown = (e) ->
    drag = true
    state = BEGIN
    points = []
    root.color = root.document.getElementById("color").value
    console.log("mouse down evt (#{e.x}, #{e.y})")

  canvas.onmouseup = (e) ->
    drag = false
    console.log("mouse up evt (#{e.x}, #{e.y})")



