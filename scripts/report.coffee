TIMEZONE = "Asia/Bangkok"
QUITTING_TIME = if process.env.REPORT_TIME then process.env.REPORT_TIME else '0 0 18 * * 2-6'
# QUITTING_TIME = '0 * * * * 2-6'

cronJob = require('cron').CronJob

module.exports = (robot) ->
  github = require("githubot")(robot)

  project_url = process.env.PROJECT_URL
  username = process.env.USERNAME
  room = process.env.ROOM

  parse_data = (array, callback, zero_callback) ->
    o = []
    unique_array = array.filter (itm,i,a) ->
      i==a.indexOf(itm) && itm? && itm != undefined && itm != ""
    for value in unique_array
      if callback?
        o.push callback(value)
      else
        o.push value
    if zero_callback? && o.length == 0
      o = zero_callback()
    o


  send_repot = ->
    # send report
    today_task = parse_data brainGet("today"), (value) ->
      "  ・" + value.split("|")[1]
    problems = parse_data brainGet("problem"), (value) ->
      "  ・" + value
    , ->
      ["  ・特にありません"]
    plans = parse_data brainGet("plan"), (value) ->
      "  ・" + value.split("|")[1]
    plans_text = ""
    plans_text = "ー明日の予定：\n" + plans.join("\n") if plans.length > 0
    # remove issue closed
    robot.brain.set "problem", null
    """
今日の日報です。
ー進捗：
#{today_task.join("\n")}
ー問題点：
#{problems.join("\n")}
#{plans_text}
"""

  brainGet = (key) ->
    data = robot.brain.get key
    if data?
      data.split('||')
    else
      []

  brainSet = (key, value) ->
    robot.brain.set key, value.join('||')

  brainAdd = (key, value) ->
    collection = brainGet(key)
    collection.push value
    brainSet key, parse_data collection

  brainRemove = (key, value) ->
    collection = brainGet(key)
    while (i = collection.indexOf(value)) >= 0
      collection.splice(i, 1)
    brainSet key, collection

  brainRemoveIndex = (key, index) ->
    collection = parse_data brainGet(key)
    collection.splice(index, 1)
    brainSet key, collection

  brainRemoveId = (key, id) ->
    id = parseInt id
    collection = brainGet(key)
    data = collection.filter (value) ->
      id == parseInt value.split("|")[0]
    brainRemove key, data[0] if data.length > 0

  task = new cronJob QUITTING_TIME, ->
    robot.messageRoom room, send_repot()
  , null, true, TIMEZONE

  robot.hear /github\.com\/[^\/]+\/[^\/]+\/issues\/([0-9]+)/i, (msg) ->
    issue_num = parseInt msg.match[1]
    github.get "#{project_url}/issues/#{issue_num}", (issue) ->
      if issue.assignee.login != username
        return

      added = brainGet("today_added").filter (value) ->
        issue_num == parseInt value
      if added.length > 0
        return

      brainAdd "today", "#{issue_num}|#{issue.title}"
      brainAdd "plan", "#{issue_num}|#{issue.title}"
      if (issue.state != "open")
        brainRemoveId "plan", issue_num

  robot.hear /github\.com\/[^\/]+\/[^\/]+\/pull\/([0-9]+)/i, (msg) ->
    pull_num = parseInt msg.match[1]
    github.get "#{project_url}/pulls/#{pull_num}", (pull) ->
      if pull.user.login != username
        return

      # find issue number
      issue_num = -1
      if !isNaN(pull.head.ref)
        issue_num = pull.head.ref
      else if pull.head.ref.match(/\#([0-9]+)/, m)
        issue_num = m.match[1]
      else if pull.body.match(/\#([0-9]+)/, m)
        issue_num = m.match[1]
      if issue_num > 0
        brainRemoveId "today", issue_num
        brainAdd "today_added", issue_num
      else
        issue_num = pull_num

      if (pull.state == "open")
        brainAdd "today", "#{pull_num}|#{pull.title}"
      if (pull.state != "open")
        brainRemoveId "plan", issue_num

  robot.respond /(problem:|問題：)\s*(.*)/i, (msg) ->
    brainAdd "problem", msg.match[2]
    msg.send "Problem #{msg.match[2]} added"

  robot.respond /debug/i, (msg) ->
    msg.send "today: " + robot.brain.get "today"
    msg.send "today_added: " + robot.brain.get "today_added"
    msg.send "problem: " + robot.brain.get "problem"
    msg.send "plan: " + robot.brain.get "plan"

  robot.respond /scheduler/i, (res) ->
    today_task = parse_data brainGet("today"), (value) ->
      "  ・" + value.split("|")[1]
    problems = parse_data brainGet("problem"), (value) ->
      "  ・" + value
    plans = parse_data brainGet("plan"), (value) ->
      "  ・" + value
    res.send "Today:\n" + today_task.join("\n")
    res.send "Problem:\n" + problems.join("\n")
    res.send "Plan:\n" + plans.join("\n")

  robot.respond /send report/i, (res) ->
    res.send send_repot()

  robot.respond /remove ([^\s]+) (.+)/i, (res) ->
    index = res.match[2]
    if isNaN(index)
      brainRemove res.match[1], res.match[2]
    else
      brainRemoveIndex res.match[1], parseInt index
    res.send "Removed #{res.match[2]} from #{res.match[1]}"

  robot.respond /clear/i, (res) ->
    robot.brain.set "problem", null
    robot.brain.set "today", null
    robot.brain.set "today_added", null
    robot.brain.set "plan", null
    res.send "Data cleared"
