module.exports = (robot) ->
  robot.router.post "/hubot/relay/:room", (req, res) ->
    room   = req.params.room
    data   = JSON.parse req.body.payload
    msg = data.msg

    robot.messageRoom room, msg
    res.send 'OK'
