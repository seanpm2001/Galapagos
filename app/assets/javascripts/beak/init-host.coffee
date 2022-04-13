loadingOverlay  = document.getElementById("loading-overlay")
modelContainer  = document.querySelector("#netlogo-model-container")
nlogoScript     = document.querySelector("#nlogo-code")

activeContainer = loadingOverlay

session = undefined

isStandaloneHTML = nlogoScript.textContent.length > 0

window.nlwAlerter = new NLWAlerter(document.getElementById("alert-overlay"), isStandaloneHTML)

window.isHNWHost = true

# (String) => String
genPageTitle = (modelTitle) ->
  if modelTitle? and modelTitle isnt ""
    "NetLogo Web: #{modelTitle}"
  else
    "NetLogo Web"

# (Session) => Unit
openSession = (s) ->
  session         = s
  document.title  = genPageTitle(session.modelTitle())
  activeContainer = modelContainer
  session.startLoop()
  if babyMonitor?
    session.entwineWithIDMan(babyMonitor)
  return

runAmbiguous = (name, args...) ->
  pp = workspace.procedurePrims
  n  = name.toLowerCase()
  if pp.hasCommand(n)
    pp.callCommand(n, args...)
    return
  else
    pp.callReporter(n, args...)

runCommand = (name, args...) ->
  workspace.procedurePrims.callCommand(name.toLowerCase(), args...)
  return

runReporter = (name, args...) ->
  workspace.procedurePrims.callReporter(name.toLowerCase(), args...)

# TODO: Temporary shim
window.runWithErrorHandling = (ignored, alsoIgnored, thunk) ->
  thunk()

# (String) => Unit
displayError = (error) ->
  # in the case where we're still loading the model, we have to
  # post an error that cannot be dismissed, as well as ensuring that
  # the frame we're in matches the size of the error on display.
  if activeContainer is loadingOverlay
    window.nlwAlerter.displayError(error, false)
    activeContainer = window.nlwAlerter.alertContainer
  else
    window.nlwAlerter.displayError(error)
  return

# (String, String) => Unit
loadModel = (nlogo, path) ->
  session?.teardown()
  window.nlwAlerter.hide()
  activeContainer = loadingOverlay
  Tortoise.fromNlogo(nlogo, modelContainer, path, openSession, displayError)
  return

# () => Unit
loadInitialModel = ->
  if nlogoScript.textContent.length > 0
    Tortoise.fromNlogo(nlogoScript.textContent,
                       modelContainer,
                       nlogoScript.dataset.filename,
                       openSession,
                       displayError)
  else if window.location.search.length > 0

    reducer =
      (acc, pair) ->
        acc[pair[0]] = pair[1]
        acc

    query    = window.location.search.slice(1)
    pairs    = query.split(/&(?=\w+=)/).map((x) -> x.split('='))
    paramObj = pairs.reduce(reducer, {})

    url       = paramObj.url ? query
    modelName = if paramObj.name? then decodeURI(paramObj.name) else undefined

    Tortoise.fromURL(url, modelName, modelContainer, openSession, displayError)

  else
    loadModel(exports.newModel, "NewModel")
  return

protocolObj = { protocolVersion: "0.0.1" }

babyMonitor = null # MessagePort

# (MessagePort, Object[Any], Array[MessagePort]?) => Unit
postToBM = (message, transfers = []) ->

  idObj    = { id: session.nextMonIDFor(babyMonitor) }
  finalMsg = Object.assign({}, message, idObj, { source: "nlw-host" })

  babyMonitor.postMessage(finalMsg, transfers)

# (Sting, Object[Any]) => Unit
broadcastHNWPayload = (type, payload) ->
  truePayload = Object.assign({}, payload, { type }, protocolObj)
  postToBM({ type: "relay", payload: truePayload })
  return

# (String, Sting, Object[Any]) => Unit
window.narrowcastHNWPayload = (uuid, type, payload) ->
  truePayload = Object.assign({}, payload, { type }, protocolObj)
  postToBM({ type: "relay", isNarrowcast: true
           , recipient: uuid, payload: truePayload })
  return

# () -> Unit
setUpEventListeners = ->

  window.clients = {}
  window.hnwGoProc = (->)

  roles = {}

  onWidgetMessage = (e) ->

    token  = e.data.token
    client = window.clients[token]
    role   = roles[client.roleName]
    who    = client.who

    switch e.data.data.type
      when "button"
        procedure = (-> runCommand(e.data.data.message))
        if role.isSpectator
          procedure()
        else
          world.turtleManager.getTurtle(who).ask(procedure, false)
      when "slider", "switch", "chooser", "inputBox"
        { varName, value } = e.data.data
        if role.isSpectator
          mangledName = "__hnw_#{role.name}_#{varName}"
          world.observer.setGlobal(mangledName, value)
        else
          world.turtleManager.getTurtle(who).ask((-> SelfManager.self().setVariable(varName, value)), false)
      when "view"
        message = e.data.data.message
        switch message.subtype
          when "mouse-down"
            if role.onCursorClick?
              thunk = (-> runAmbiguous(role.onCursorClick, message.xcor, message.ycor))
              if role.isSpectator
                thunk()
              else
                world.turtleManager.getTurtle(who).ask(thunk, false)
          when "mouse-up"
            if role.onCursorRelease?
              thunk = (-> runAmbiguous(role.onCursorRelease, message.xcor, message.ycor))
              if role.isSpectator
                thunk()
              else
                world.turtleManager.getTurtle(who).ask(thunk, false)
          when "mouse-move"
            if role.isSpectator
              if role.cursorXVar?
                mangledName = "__hnw_#{role.name}_#{role.cursorXVar}"
                world.observer.setGlobal(mangledName, message.xcor)
              if role.cursorYVar?
                mangledName = "__hnw_#{role.name}_#{role.cursorYVar}"
                world.observer.setGlobal(mangledName, message.ycor)
            else
              turtle = world.turtleManager.getTurtle(who)
              if role.cursorXVar?
                turtle.ask((-> SelfManager.self().setVariable(role.cursorXVar, message.xcor)), false)
              if role.cursorYVar?
                turtle.ask((-> SelfManager.self().setVariable(role.cursorYVar, message.ycor)), false)
          else
            console.warn("Unknown HNW View event subtype")
      else
        console.warn("Unknown HNW widget event type")


  onRaincheckMessage = (e) ->
    imageBase64 = session.cashRainCheckFor(e.data.hash)
    imageUpdate = { type: "import-drawing", imageBase64, hash: e.data.hash }
    viewUpdate  = { drawingEvents: [imageUpdate] }
    session.narrowcast(e.data.token, "nlw-state-update", { viewUpdate })

  onBabyMonitorMessage = (e) ->

    switch (e.data.type)

      when "hnw-recompile"
        console.log("RECOMPILE")
        session.recompile(() => {})

      when "hnw-recompile-lite"
        console.log("RECOMPILE LITE")
        session.recompileLite(() => {})

      when "hnw-console-run"
        session.run(e.data.code, () => {})

      when "hnw-setup-button"
        runCommand("setup")

      when "hnw-go-checkbox"
        runCommand("go")

      when "hnw-widget-message"
        onWidgetMessage(e)

      when "hnw-cash-raincheck"
        onRaincheckMessage(e)

      when "hnw-become-oracle"
        loadModel(e.data.nlogo, "Jason's Experimental Funland")

        session.widgetController.ractive.observe(
          "consoleOutput",
          (newValue, oldValue, keyPath) ->
            if newValue?
              newValuesArr = newValue.split("\n")

              if newValuesArr.length != 1
                newOutputLine = newValuesArr.at(-2)
                postToBM({ type: "nlw-command-center-output", newOutputLine })
        )

        session.widgetController.ractive.set("isHNW"    , true)
        session.widgetController.ractive.set("isHNWHost", true)

        header = document.querySelector('.netlogo-header')

        exiles =
          [ header.querySelector('.netlogo-subheader')
          , header.querySelector('.flex-column')
          , document.querySelector('.netlogo-model-title')
          , document.querySelector('.netlogo-toggle-container')
          ]

        # Spectator Mode!

        exiles.forEach((n) -> n.style.display = "none")

        wContainer = document.querySelector('.netlogo-widget-container')
        parent     = wContainer.parentNode # TODO: Name shadowing?

        flexbox                      = document.createElement("div")
        flexbox.id                   = "main-frames-container"
        flexbox.style.display        = "flex"
        flexbox.style.flexDirection  = "row"
        flexbox.style.width          = "97vw"
        flexbox.style.justifyContent = "space-between"

        parent.replaceChild(flexbox, wContainer)

        # (NEW): Add flexbox for text above supervisor (teacher) & student views
        titlesFlexbox                      = document.createElement("div")
        titlesFlexbox.style.display        = "flex"
        titlesFlexbox.style.flexDirection  = "row"
        titlesFlexbox.style.justifyContent = "center"

        supervisorTitle                   = document.createElement("p")
        supervisorTitle.innerHTML         = "Teacher"
        supervisorTitle.style.fontSize    = "24px"
        supervisorTitle.style.marginRight = "45vw"

        studentTitle                = document.createElement("p")
        studentTitle.innerHTML      = "Student"
        studentTitle.style.fontSize = "24px"

        titlesFlexbox.appendChild(supervisorTitle)
        titlesFlexbox.appendChild(studentTitle)

        parent.insertBefore(titlesFlexbox, document.getElementById("main-frames-container"))

        baseView = session.widgetController.widgets().find(({ type }) -> type is 'view')

        # TODO: Temporarily comment out these lines to remove accordion tabs from inner frame
        tabAreaElem = document.querySelector(".netlogo-tab-area")
        taeParent   = tabAreaElem.parentNode

        if e.data.targetFrameRate?
          session.setTargetFrameRate(e.data.targetFrameRate)

        genUUID = ->

          replacer =
            (c) ->
              r = Math.random() * 16 | 0
              v = if c == 'x' then r else (r & 0x3 | 0x8)
              v.toString(16)

          'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, replacer)

        roles = {}
        e.data.roles.forEach((role) -> roles[role.name] = role)

        for roleName, role of roles
          for widget in role.widgets
            if widget.type is "hnwMonitor"
              monitor = widget
              safely = (f) -> (x) ->
                try workspace.dump(f(x))
                catch ex
                  "N/A"
              func =
                switch monitor.reporterStyle
                  when "global-var"
                    do (monitor) -> safely(-> world.observer.getGlobal(monitor.source))
                  when "procedure"
                    do (monitor) -> safely(-> runReporter(monitor.source))
                  when "turtle-var"
                    plural = world.breedManager.getSingular(roleName).name
                    do (monitor) -> safely((who) -> world.turtleManager.getTurtleOfBreed(plural, who).getVariable(monitor.source))
                  when "turtle-procedure"
                    plural = world.breedManager.getSingular(roleName).name
                    do (monitor) -> safely((who) -> world.turtleManager.getTurtleOfBreed(plural, who).projectionBy(-> runReporter(monitor.source)))
                  else
                    console.log("We got '#{monitor.reporterStyle}'?")
              session.registerMonitorFunc(roleName, monitor.source, func)

        supervisorFrame     = document.createElement("iframe")
        supervisorFrame.id  = "hnw-join-frame"
        supervisorFrame.src = "/hnw-join"

        supervisorFrame.style.border = "3px solid black"
        supervisorFrame.style.height = "100vh"
        supervisorFrame.style.width  = "47vw"
        supervisorFrame.style.margin = "0 auto"

        flexbox.appendChild(supervisorFrame)

        session.widgetController.ractive.observe(
          'ticksStarted'
        , (newValue, oldValue) ->
            if (newValue isnt oldValue)
              broadcastHNWPayload("ticks-started", { value: newValue })
        )

        supervisorFrame.addEventListener('load', ->

          uuid = genUUID()
          role = Object.values(roles)[1]

          wind = supervisorFrame.contentWindow

          window.clients[uuid] =
            { roleName:    role.name
            , perspVar:    role.perspectiveVar
            }

          # NOTE
          if role.onConnect?
            runAmbiguous(role.onConnect, "the supervisor")

          session.initSamePageClient( uuid, uuid, handleJoinerMsg, wind
                                    , role, baseView)

        )

        studentFrame     = document.createElement("iframe")
        studentFrame.id  = "hnw-join-frame"
        studentFrame.src = "/hnw-join"

        studentFrame.style.border    = "3px solid black"
        studentFrame.style.height    = "80vh"
        studentFrame.style.width     = "47vw"

        flexbox.appendChild(studentFrame)

        studentFrame.addEventListener('load', ->

          genUUID = ->

            replacer =
              (c) ->
                r = Math.random() * 16 | 0
                v = if c == 'x' then r else (r & 0x3 | 0x8)
                v.toString(16)

            'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, replacer)

          uuid = genUUID()
          role = Object.values(roles)[0]
          # NOTE

          wind = studentFrame.contentWindow

          username = "Fake Client"
          who      = null

          # NOTE
          if role.onConnect?
            result = runAmbiguous(role.onConnect, username)
            if typeof result is 'number'
              who = result

          # NOTE
          window.clients[uuid] =
            { roleName:    role.name
            , perspVar:    role.perspectiveVar
            , username
            , who
            }

          session.initSamePageClient( e.data.token, uuid, handleJoinerMsg, wind
                                    , role, baseView)

        )

      when "hnw-notify-congested"
        session.enableCongestionControl()

      when "hnw-notify-uncongested"
        session.disableCongestionControl()

      when "hnw-request-initial-state"

        viewState = session.widgetController.widgets().find(({ type }) -> type is 'view')
        role      = roles[e.data.roleName]

        username = e.data.username
        who      = null

        # NOTE
        if role.onConnect?
          result = runAmbiguous(role.onConnect, username)
          if typeof result is 'number'
            who = result

        window.clients[e.data.token] =
          { roleName:    role.name
          , perspVar:    role.perspectiveVar
          , username
          , who
          }

        session.updateWithoutRendering(e.data.token)

        # NOTE
        monitorUpdates = session.monitorsFor(e.data.token)
        state          = Object.assign({}, session.getModelState(""), { monitorUpdates })

        type       = "hnw-initial-state"
        msg        = { token: e.data.token, role, state, viewState, type }
        respondent = e.ports?[0] ? babyMonitor
        respondent.postMessage(msg)

        session.subscribeWithID(null, e.data.token)

      when "hnw-notify-disconnect"

        id = e.data.joinerID

        if window.clients[id]?

          { roleName, who } = window.clients[id]
          onDC              = roles[roleName].onDisconnect

          delete window.clients[id]
          session.unsubscribe(id)

          turtle = world.turtleManager.getTurtle(who)

          if onDC?
            turtle.ask((-> runAmbiguous(onDC)), false)

          if not turtle.isDead()
            turtle.ask((-> SelfManager.self().die()), false)

          session.updateWithoutRendering("")

      when "nlw-request-view"

        respondWithView =
          ->
            respondent = e.ports?[0] ? babyMonitor
            session.widgetController.viewController.view.visibleCanvas.toBlob(
              (blob) -> respondent.postMessage({ blob, type: "nlw-view" })
            )

        session.widgetController.viewController.repaint()
        setTimeout(respondWithView, 0) # Relinquish control for a sec so `repaint` can go off --JAB (9/8/20)

      when "nlw-subscribe-to-updates"

        if not window.clients[e.data.uuid]?
          window.clients[e.data.uuid] = {}

        session.subscribeWithID(babyMonitor, e.data.uuid)

      when "hnw-latest-ping"
        window.clients[e.data.joinerID]?.ping = e.data.ping

      when "nlw-state-update", "nlw-apply-update"

        { widgetUpdates, monitorUpdates, plotUpdates, viewUpdate } = e.data.update

        if viewUpdate?.world?[0]?.ticks?
          world.ticker.reset()
          world.ticker.importTicks(viewUpdate.world.ticks)

        if widgetUpdates?
          session.widgetController.applyWidgetUpdates(widgetUpdates)

        if plotUpdates?
          session.widgetController.applyPlotUpdates(plotUpdates)

        if viewUpdate?
          vc = session.widgetController.viewController
          vc.applyUpdate(viewUpdate)
          vc.repaint()

      else
        console.warn("Unknown babyMon message type:", e.data)

  relayIDMan = new window.IDManager()

  handleJoinerMsg = (e) ->
    switch e.data.type
      when "relay"
        id  = relayIDMan.next("")
        msg = Object.assign({}, e.data.payload, { id }, { source: "frame-relay" })
        window.postMessage(msg)
      when "hnw-fatal-error"
        postToBM(e.data)
      when "noop"
      else
        console.warn("Unknown inner joiner message:", e.data)

  window.addEventListener("message", (e) ->

    switch e.data.type

      when "hnw-widget-message"
        onWidgetMessage(e)

      when "hnw-cash-raincheck"
        onRaincheckMessage(e)

      when "nlw-load-model"
        loadModel(e.data.nlogo, e.data.path)
      when "nlw-open-new"
        loadModel(exports.newModel, "NewModel")
      when "nlw-update-model-state"
        session.widgetController.setCode(e.data.codeTabContents)
      when "run-baby-behaviorspace"
        parcel   = { type: "baby-behaviorspace-results", id: e.data.id, data: results }
        reaction = (results) -> e.source.postMessage(parcel, "*")
        session.asyncRunBabyBehaviorSpace(e.data.config, reaction)
      when "nlw-request-model-state"
        update = session.getModelState("")
        e.source.postMessage({ update, type: "nlw-state-update", sequenceNum: -1 }, "*")
      when "hnw-set-up-baby-monitor"
        babyMonitor           = e.ports[0]
        babyMonitor.onmessage = onBabyMonitorMessage

        # (NEW): Pass model code & info to HNW
        setTimeout ->
          modelCode = session.widgetController.ractive.get('code')
          postToBM({ type: "nlw-model-code", code: modelCode })

          modelInfo = session.widgetController.ractive.get('info')
          postToBM({ type: "nlw-model-info", info: modelInfo })
        , 1000

        # TODO: Should eventually remove this^^ timeout & set an observer
        # session.widgetController.ractive.observe('lastCompiledCode', alertCode)

      when "hnw-resize"

        isValid = (x) -> x?

        height = e.data.height
        width  = e.data.width
        title  = e.data.title

        if [height, width, title].every(isValid)
          elem           = document.getElementById("hnw-join-frame")
          elem.width     = width
          elem.height    = height
          document.title = title

      else
        console.warn("Unknown init-host postMessage:", e.data)

    return

  )

  return

# () => Unit
handleFrameResize = ->

  if parent isnt window

    width  = ""
    height = ""

    onInterval =
      ->
        if (activeContainer.offsetWidth  isnt width or
            activeContainer.offsetHeight isnt height or
            (session? and document.title isnt genPageTitle(session.modelTitle())))

          if session?
            document.title = genPageTitle(session.modelTitle())

          width  = activeContainer.offsetWidth
          height = activeContainer.offsetHeight

          parent.postMessage({
            width:  activeContainer.offsetWidth,
            height: activeContainer.offsetHeight,
            title:  document.title,
            type:   "nlw-resize"
          }, "*")

    window.setInterval(onInterval, 200)

  return

loadInitialModel()
setUpEventListeners()
handleFrameResize()
