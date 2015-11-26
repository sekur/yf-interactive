# web browser interface feature module
#
# This feature add-on module enables generation of a web-based client
# application based on the underlying [express](express.yaml) and
# [websocket](websocket.yaml) feature add-ons to dynamically generate
# user friendly YF runtime browsing capability.
#
# It makes use of following web frameworks:
#
# bootstrap (css)
# handlebars (template)
# coffeescript (language)
# react (facebook UI library)
# socket.io (websocket)
# browserify (generate client-side js bundle)

module.exports =
  run: (model, runtime) ->
    app = model.parent
    pkgdir = app.meta 'pkgdir'

    path = require 'path'
    express = require 'express'
    exphbs  = require 'express-handlebars'
    browser = (->
      @engine 'hbs', exphbs
        defaultLayout: 'main'
        extname: 'hbs'
        layoutsDir: "#{pkgdir}/views"
      @set 'view engine', 'hbs'
      @set 'views', "#{pkgdir}/views"

    ).call express()

    reactive = [
      'moment',
      'react', 'react-dom'
      'react-highlight'
      'react-widgets'
      'react-textarea-autosize'
      'zingchart'
    ]
    browserify = require 'browserify'
    sbuf = require 'stream-buffers'
    yfx = new sbuf.ReadableStreamBuffer initialSize: 1024
    yfx.put "source = atob('#{app.constructor.toSource format: 'yaml', encoding: 'base64'}');", 'utf8'
    yfx.put "Forge = require('#{pkgdir}');", 'utf8'
    b = browserify yfx, basedir: pkgdir
    b.add require.resolve 'coffee-script/lib/coffee-script/browser'
    for x in reactive
      b.add (require.resolve x), expose: x
    b.add (require.resolve 'react-widgets/lib/localizers/moment'), expose: 'moment-localizer'
    b.ignore x for x in [ 'prettyjson' ]
    if @config.uglify is true
      b.transform global: true, sourcemap: false, (require 'uglifyify')

    console.info "browser: yangforge browserification started (will take a few seconds)".grey
    b.bundle (err, js) ->
      console.info "browser: yangforge browserification complete".grey
      browser.get '/', (req, res) -> res.render 'index', layout: 'browser', version: app.meta 'version'
      browser.get '/yangforge.js', (req, res) ->
        res.type 'application/javascript'
        res.send js
      highlight = path.resolve pkgdir, 'node_modules/highlight.js/styles'
      browser.get '/highlight/:style.css', (req, res, next) ->
        (require 'fs').readFile "#{highlight}/#{req.params.style}.css", (err, data) ->
          return next err if err?
          res.type 'text/css'
          res.send data
      # TODO: this is UGLY...
      widgets = path.resolve pkgdir, 'node_modules/react-widgets/dist'
      browser.get '/styles/react-widgets.css', (req, res, next) ->
        (require 'fs').readFile "#{widgets}/css/react-widgets.css", (err, data) ->
          return next err if err?
          res.type 'text/css'
          res.send data
      browser.get '/fonts/:font', (req, res, next) ->
        (require 'fs').readFile "#{widgets}/fonts/#{req.params.font}", (err, data) ->
          return next err if err?
          res.send data

      zingchart = path.resolve pkgdir, 'node_modules/zingchart/client/modules'
      browser.get '/zingchart/modules/:script', (req, res, next) ->
        (app.require 'fs').readFile "#{zingchart}/#{req.params.script}", (err, data) ->
          return next err if err?
          res.send data

    yfx.destroySoon()

    if runtime.express?
      console.info "browser: binding to express /browser".grey
      runtime.express.app.use "/browser", browser

    if runtime.websocket?
      console.info "browser: binding to websocket /browser".grey
      io = runtime.websocket.of '/browser'
      io.on 'connection', (socket) ->
        console.log 'User connected. socket id %s', socket.id
        socket.on 'knock', (rooms) ->
          rooms = [ rooms ] unless Array.isArray rooms
          console.log '[socket:%s] Knocking on %s', socket.id, rooms
          keys = (
            rooms
            .map (room) ->
              # ok this is kinda long and ugly... haha
              (app.access room)?.parent.constructor.toSource? format: 'yaml'
            .filter (x) -> x?
            .map (x) -> source: x
          )
          socket.emit 'infuse', targets: keys

        socket.on 'join', (rooms) ->
          console.log '[socket:%s] Joining %s', socket.id, rooms
          if Array.isArray rooms
            socket.join room for room in rooms
          else
            socket.join rooms
        socket.on 'leave', (rooms) ->
          console.log '[socket:%s] Leaving %s', socket.id, rooms
          if Array.isAray rooms
            socket.leave room for room in rooms
          else
            socket.leave rooms
        socket.emit 'rooms', Object.keys(app.properties)

      # watch app and send events
      app.on 'attach', (name, room) ->
        source = room?.parent?.constructor.toSource? format: 'yaml'
        console.log "attached #{name}"
        io.emit 'infuse', sources: source if source?
        #io.to(room).emit type, message

    return browser
