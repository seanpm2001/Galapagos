infoModalMonitor = null # MessagePort
ractive = null # Ractive

loadInfoModal = ->

  # (NEW): Handle messages to info modal window (iframe)
  window.addEventListener("message", (e) ->

    switch (e.data.type)
      when "hnw-set-up-info-modal"
        infoModalMonitor = e.ports[0]
        infoModalMonitor.onmessage = onInfoModalMessage
        return

    console.warn("Unknown info modal postMessage:", e.data)
  )

  # (NEW): Info modal setup
  template = """
    <label class="netlogo-tab netlogo-active">
        <input id="info-toggle" type="checkbox" checked="true" />
        <span class="netlogo-tab-text">Model Info</span>
      </label>
    <infotab rawText='{{info}}' isEditing='false' />
  """

  ractive = new Ractive({
    el:       document.getElementById("info-modal-container")
    template: template,
    components: {
      infotab: RactiveInfoTabWidget
    },
    data: -> {
      info: ""
    }
  })

onInfoModalMessage = (e) ->

  switch (e.data.type)
    when "hnw-model-info"
      ractive.set("info", e.data.info)

loadInfoModal()
