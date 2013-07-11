root = this

dsconf = {}

if (typeof exports isnt 'undefined')
  if (typeof module isnt 'undefined' and module.exports)
    exports = module.exports = dsconf
  exports.dsconf = dsconf
else
  root.dsconf = dsconf

dscriptServer = 'ws://localhost:9090'

controllerPath = '/dscript/controller'
controllerURL = dscriptServer + controllerPath

readerPrefixPath = '/dscript/reader'
readerPrefixURL = dscriptServer + readerPrefixPath

writerPrefixPath = '/dscript/writer'
writerPrefixURL = dscriptServer + writerPrefixPath

root.dsconf.dscriptServer = dscriptServer

root.dsconf.controllerPath = controllerPath
root.dsconf.controllerURL  = controllerURL

root.dsconf.readerPrefixPath = readerPrefixPath
root.dsconf.readerPrefixURL = readerPrefixURL

root.dsconf.writerPrefixPath = writerPrefixPath
root.dsconf.writerPrefixURL = writerPrefixURL

