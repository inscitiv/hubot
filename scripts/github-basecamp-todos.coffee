# Description:
#   Closes Basecamp todo-list items in response to pushes on github.
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_BASECAMP_TOKEN    -  Your API key
#   HUBOT_BASECAMP_ACCOUNT  -  Your basecamp account
#
# Commands:
#   None
#
# URLS:
#   POST /hubot/gh-basecamp-todos
#
# Notes:
#   If you also have our hacked up version of github-commits,
#   you don't need to add the additional webhook on github.
#
# Authors:
#   jjmason
Util = require 'util'
_ = require 'underscore'
module.exports = (robot) ->
  # TODO Delete me!
  robot.logger.level = 'debug'

  robot.router.post '/hubot/gh-basecamp-todos', (req, res) ->
    res.end()
    payload = req.body?.payload

    return robot.logger.error "no payload in github post #{Util.inspect req.body}" unless payload?

    try
      payload = JSON.parse payload
      handle_payload robot, payload
    catch e
      robot.logger.error("error processing github post: #{e}\npayload: #{Util.inspect payload}")
  robot.on 'github:post', (payload) ->
    handle_payload(robot, payload, true)

handle_payload = (robot, payload, isEvent = false) ->
  robot.logger.debug "github payload #{Util.inspect payload} from #{if isEvent then 'event' else 'post'}"

  commits = (payload.commits ||= [])
  if payload.head_commit?
   commits.unshift payload.head_commit
  commits = _.uniq payload.commits, (commit) -> commit.id
  
  todo_ids = []
  commits.each (commit) ->
    todo_ids = todo_ids.concat handle_commit(robot, commit)

  todo_ids = _.uniq todo_ids, _.identity

  robot.logger.debug "got #{Util.inspect todo_ids} todos"

