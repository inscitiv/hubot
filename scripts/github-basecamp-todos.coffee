# Description:
#   Closes Basecamp todo-list items in response to pushes on github.
#
# Dependencies:
#   underscore: 1.4.x
#
# Configuration:
#   * Note: These don't start with HUBOT so the getenv script will hide them.   
#
#   BASECAMP_USERNAME     -  Your Hubot's username
#   BASECAMP_PASSWORD     -  The associated password
#
#   * You can get these from a url like https://basecamp.com/11111111/projects/22222222-my-project-name
#   HUBOT_BASECAMP_ACCOUNT      -  Your basecamp account, 11111111 in the above url
#   HUBOT_BASECAMP_PROJECT      -  Your basecamp project, 22222222 in the above url
# 
#   HUBOT_TODOS_ROOMS   - A comma separated list of room ids where we anounce completed todos.
#                         Leave this blank if you don't want to hear about that.
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
{STATUS_CODES}= require 'http'
_ = require 'underscore'

class GithubBasecampTodos
  constructor: (@robot) ->
    @robot.router.post '/hubot/gh-basecamp-todos',@postHandler
    @robot.on 'github:post', @eventHandler
    @robot.respond /complete(?: basecamp)?(?: todo)?\s*(\d+)/i, @commandHandler
    @seenCommits = {}
    
  commandHandler: (msg) =>
    id = msg.match[1]
    msg.reply "OK, trying to finish TODO #{id}"
    @closeTodo id, (err, res) =>
      if err
        msg.send "And...FAIL! I couldn't complete your TODO #{id}: #{err}"
      else
        msg.send "Hooray, TODO #{id} is complete!!"
    
  postHandler: (req,res) =>
    res.end()
    @payload = req.body?.payload
    return @robot.logger.error "no payload in github post #{Util.inspect req.body}" unless @payload?
    @payload = JSON.parse payload
    @finishTodos()
  
  eventHandler: (@payload) =>
    @finishTodos()
  
  finishTodos: =>
    # @robot.logger.debug "finishTodos in #{Util.inspect @payload}"
    # don't mess commits up for other listeners!
    commits = _.clone(@payload.commits || [])
    if @payload.head_commit?
     commits.unshift @payload.head_commit
    
    # delete commits we've already handled
    commits = _.reject commits, (commit) =>
      if @seenCommits[commit.id]
        @robot.logger.debug "skipping #{commit.id}, already seen it!"
        true
      else
        @seenCommits[commit.id] = true
        false
    @todoIds = []
    _.each commits, @processCommit
    @todoIds = _.uniq @todoIds, _.identity
    @robot.logger.debug "got #{Util.inspect @todoIds} todos"
    _.each @todoIds, (id) =>
      @spam "Got commit with magic text, trying to complete the basecamp todo #{id}"
      @closeTodo id, (err, res) =>
        if err
          @robot.logger.error("Closing todo: #{err}")
          @spam "Oh hamburgers! I couldn't complete TODO #{id} because of #{err}"
        else
          @spam "Hooray, TODO #{id} is complete!"

  spam: (text, room) =>
    if arguments.length < 2
      rooms = process.env.HUBOT_TODO_ROOMS?.split(',')
      if rooms?.length
        rooms.forEach (room) =>
          @spam(text, room)
    else
      user = {room : room}
      @robot.send user, text

  processCommit: (commit) =>
    hot_text = /BC#(\d+)/ig 
    if (msg = commit.message)?
      while (match = hot_text.exec(msg))?
        @todoIds.push match[1]
    
  closeTodo: (id, cb) =>
    @robot.logger.debug("Closing Basecamp TODO: #{@todoUrl(id)}")
    @robot.http("#{@todoUrl(id)}")
      .auth(process.env.BASECAMP_USERNAME,process.env.BASECAMP_PASSWORD)
      .header("Content-Type", "application/json")
      .put(@closeTodoBody()) (err, res, body) =>
        fail = (why) =>
          cb(why) if _.isFunction(cb)
          @robot.logger.error("Error  closing todo: #{why}")
        win = =>
          cb(null, true) if  _.isFunction(cb)
          @robot.logger.debug("TODO closed!")
        return fail(err) if err
        sc = res.statusCode
        return fail("Basecamp returned status #{sc} #{STATUS_CODES[sc]}") if sc != 200
        win()
  
  todoUrl: (id) =>
    "https://basecamp.com/#{process.env.HUBOT_BASECAMP_ACCOUNT}" + 
      "/api/v1/projects/#{process.env.HUBOT_BASECAMP_PROJECT}/todos/#{id}.json"
    
  closeTodoBody: ->
    JSON.stringify({completed:true})
    
  responseHandler: (err, res, body) =>
    if err
      @robot.logger.error "Error #{err} while closing todo"
    if res.statusCode != 200
      @robot.logger.error "Basecamp returned status code #{res.statusCode} #{STATUS_CODES[res.statusCode]}"
    if body?
      try
        json = JSON.parse body
        if json.completed?
          @robot.logger.info "Basecamp TODO##{json.id} is now completed: #{json.completed}"
        else
          @robot.logger.error "Got funny response from basecamp: #{Util.inspect json}"
      catch e
        @robot.logger.error "Error parsing basecamp response JSON: #{e}"
        return
      
      
module.exports = (robot) ->
  new GithubBasecampTodos(robot)


  
