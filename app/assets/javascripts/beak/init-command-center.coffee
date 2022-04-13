commandCenterMonitor = null # MessagePort
ractive = null # Ractive
compiler = new BrowserCompiler()
codeTab = ""
widgets = []
hnwPortToIDMan = new Map()

loadCodeModal = ->

  # (NEW): Handle messages to command center window (iframe)
  window.addEventListener("message", (e) ->

    switch (e.data.type)
      when "hnw-set-up-command-center"
        commandCenterMonitor = e.ports[0]
        commandCenterMonitor.onmessage = onCommandCenterMessage
        result = compiler.fromNlogo(e.data.nlogo)

        codeTab = result.code
        widgets = JSON.parse(result.widgets)
        hnwPortToIDMan.set(commandCenterMonitor, new window.IDManager())

        return

    console.warn("Unknown command center postMessage:", e.data)
  )

  # compiler = new BrowserCompiler()
  checkIsReporter = (str) => compiler.isReporter(str)

  # (NEW): Command center setup
  template = """
    <console output="{{consoleOutput}}" isEditing="false" checkIsReporter="{{checkIsReporter}}" />
  """

  ractive = new Ractive({
    el:       document.getElementById("netlogo-command-center-container")
    template: template,
    components: {
      console: RactiveConsoleWidget
    },
    data: -> {
      consoleOutput: "",
      checkIsReporter: checkIsReporter
    }
  })

  ractive.on('console.run', (_, code, errorLog) => postToBM({ type: "hnw-console-run", code }))

# (MessagePort) => Number
nextMonIDFor = (port) ->
  hnwPortToIDMan.get(port).next("")

# (MessagePort, Object[Any], Array[MessagePort]?) => Unit
postToBM = (message, transfers = []) ->

  idObj    = { id: nextMonIDFor(commandCenterMonitor) }
  finalMsg = Object.assign({}, message, idObj, { source: "nlw-host" })

  commandCenterMonitor.postMessage(finalMsg, transfers)

# TODO
onCommandCenterMessage = (e) ->
  switch (e.data.type)
    when "hnw-command-center-output"
      oldConsoleOutput = ractive.get("consoleOutput")
      ractive.set("consoleOutput", oldConsoleOutput + e.data.newOutputLine + "\n")

loadCodeModal()
