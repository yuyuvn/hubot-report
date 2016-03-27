module.exports = (robot) ->
  robot.router.post "/hubot/relay/:room", (req, res) ->
    room = req.params.room
    msg = req.body.msg
    robot.messageRoom room, msg
    res.send 'OK'
