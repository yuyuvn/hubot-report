TIMEZONE = "Asia/Bangkok"
QUITTING_TIME = if process.env.REPORT_TIME then process.env.REPORT_TIME else '0 0 18 * * 1-5'
STARTING_TIME = if process.env.START_TIME then process.env.START_TIME else '0 0 7 * * 1-5'
# QUITTING_TIME = '0 * * * * *'

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

  check_list = (type, custom_condition) ->
    if !custom_condition
      custom_condition = (issue, value) ->
        issue.state != "open" ||
          (issue.assignee && issue.assignee.login != username)

    list = brainGet type
    for value in list
      issue_num = parseInt value.split("|")[0]
      break if issue_num < 0
      github.get "#{project_url}/issues/#{issue_num}", (issue) ->
        if custom_condition(issue,value)
          brainRemove type, value

  report = ->
    today_task = parse_data brainGet("today"), (value) ->
      "  ・" + value.split("|")[1]
    today_task_english = parse_data brainGet("today"), (value) ->
      "  ・" + value.split("|")[2]
    problems = parse_data brainGet("problem"), (value) ->
      "  ・" + value
    , ->
      ["  ・特にありません"]
    plans = parse_data brainGet("plan"), (value) ->
      "  ・" + value.split("|")[1]
    plans_text = ""
    plans_text = "ー明日の予定：\n" + plans.join("\n") if plans.length > 0
    plans_english = parse_data brainGet("plan"), (value) ->
      "  ・" + value.split("|")[2]
    plans_text_english = ""
    plans_text_english = "---\n" + plans_english.join("\n") if plans_english.length > 0
    """
今日の日報です。
ー進捗：
#{today_task.join("\n")}
---
#{today_task_english.join("\n")}
ー問題点：
#{problems.join("\n")}
#{plans_text}
#{plans_text_english}
"""

  send_report = ->
    # before-process
    check_list("plan")

    report_text = report()

    report_text

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
    removed = []
    while (i = collection.indexOf(value)) >= 0
      removed = collection.splice(i, 1)
    brainSet key, collection
    removed[0]

  brainRemoveIndex = (key, index) ->
    collection = parse_data brainGet(key)
    removed = collection.splice(index, 1)
    brainSet key, collection
    removed[0]

  brainRemoveId = (key, id) ->
    id = parseInt id
    collection = brainGet(key)
    data = collection.filter (value) ->
      id == parseInt value.split("|")[0]
    brainRemove key, data[0] if data.length > 0

  brainGetId = (key, id) ->
    id = parseInt id
    collection = brainGet(key)
    data = collection.filter (value) ->
      id == parseInt value.split("|")[0]
    data[0]

  task = new cronJob QUITTING_TIME, ->
    robot.messageRoom room, send_report()
  , null, true, TIMEZONE

  task2 = new cronJob STARTING_TIME, ->
    check_list("plan")
    robot.brain.set "problem", null
    robot.brain.set "today", robot.brain.get "plan"
  , null, true, TIMEZONE

  robot.hear /github\.com\/[^\/]+\/[^\/]+\/issues\/([0-9]+)/i, (msg) ->
    issue_num = parseInt msg.match[1]
    github.get "#{project_url}/issues/#{issue_num}", (issue) ->
      if issue.assignee.login != username
        return

      return if brainGetId("today", issue_num)

      # find english translation
      english = if m = pull.body.match(/\*\[(.+)\]\*/) then m[1] else ""

      if (issue.state == "open")
        brainAdd "today", "#{issue_num}|#{issue.title}|#{english}"
        brainAdd "plan", "#{issue_num}|#{issue.title}|#{english}"

  robot.hear /github\.com\/[^\/]+\/[^\/]+\/pull\/([0-9]+)/i, (msg) ->
    pull_num = parseInt msg.match[1]
    github.get "#{project_url}/pulls/#{pull_num}", (pull) ->
      if pull.user.login != username
        return

      # find issue number
      issue_num = -1
      if !isNaN(pull.head.ref)
        issue_num = pull.head.ref
      else if m = pull.head.ref.match(/\#([0-9]+)/)
        issue_num = m[1]
      else if m = pull.body.match(/\#([0-9]+)/)
        issue_num = m[1]
      if issue_num > 0
        brainRemoveId "today", issue_num
        brainRemoveId "plan", issue_num
      else
        issue_num = pull_num

      # find english translation
      english = if m = pull.body.match(/\*\[(.+)\]\*/) then m[1] else ""

      if (pull.state == "open")
        brainAdd "today", "#{issue_num}|#{pull.title}|#{english}"
        brainAdd "plan", "#{issue_num}|#{pull.title}|#{english}"

  robot.respond /(problem:|問題：)\s*(.*)/i, (msg) ->
    brainAdd "problem", msg.match[2]
    msg.reply "Problem #{msg.match[2]} added"

  robot.respond /debug/i, (msg) ->
    msg.reply """
today: #{robot.brain.get "today"}
problem: #{robot.brain.get "problem"}
plan: #{robot.brain.get "plan"}
"""

  robot.respond /scheduler/i, (res) ->
    res.reply report()

  robot.respond /send report/i, (res) ->
    res.reply send_report()

  robot.respond /remove ([^\s]+) (.+)/i, (res) ->
    index = res.match[2]
    removed = ""
    if isNaN(index)
      removed = brainRemove res.match[1], res.match[2]
    else
      removed = brainRemoveIndex res.match[1], parseInt index
    res.reply "Removed \"#{removed}\" from #{res.match[1]}"

  robot.respond /clear/i, (res) ->
    robot.brain.set "problem", null
    robot.brain.set "today", null
    robot.brain.set "plan", null
    res.reply "Data cleared"

  robot.respond /add ([^\s]+) (.+)/i, (res) ->
    if res.match[1] == "today" || res.match[1] == "plan"
      brainAdd res.match[1], "-1|#{res.match[2]}"
    else
      brainAdd res.match[1], res.match[2]
    res.reply "Added \"#{res.match[2]}\" to #{res.match[1]}"
