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
    msg.reply "ok, trying to finish #{id}"
    @closeTodo(id)
    
  postHandler: (req,res) =>
    res.end()
    @payload = req.body?.payload
    return @robot.logger.error "no payload in github post #{Util.inspect req.body}" unless @payload?
    @payload = JSON.parse payload
    @finishTodos()
  
  eventHandler: (@payload) =>
    @finishTodos()
  
  finishTodos: =>
    @robot.logger.debug "finishTodos in #{Util.inspect @payload}"
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
    _.each @todoIds, @closeTodo
    
  processCommit: (commit) =>
    hot_text = /BC#(\d+)/ig 
    if (msg = commit.message)?
      while (match = hot_text.exec(msg))?
        @todoIds.push match[1]
    
  closeTodo: (id) =>
    pass = process.env.BASECAMP_PASSWORD
    user = process.env.BASECAMP_USERNAME
    auth = new Buffer("#{user}:#{pass}").toString('base64') 
    @robot.logger.debug("using basic-auth:#{user}:#{pass}")
    @robot.logger.debug("sending to: #{@todoUrl(id)}")
    @robot.http("#{@todoUrl(id)}")
      .auth(user,pass)
      .header("Content-Type", "application/json")
      .put(@closeTodoBody())(@responseHandler)

  
  todoUrl: (id) =>
    "https://basecamp.com/#{process.env.HUBOT_BASECAMP_ACCOUNT}" + 
      "/api/v1/projects/#{process.env.HUBOT_BASECAMP_PROJECT}/todos/#{id}.json"
    
  closeTodoBody: ->
    JSON.stringify({completed:true})
    
  responseHandler: (err, res, body) =>
    @robot.logger.debug "response from basecamp:#{err},#{res.statusCode}\n#{res.body}"
    if err
      @robot.logger.error "Error #{err} while closing todo"
    if res.statusCode != 200
      @robot.logger.error "Basecamp returned status code #{res.statusCode} #{STATUS_CODES[res.statusCode]}"
    if res.body?
      try
        json = JSON.parse res.body
        if json.complete?
          @robot.logger.info "TODO #{json.id} is now complete: #{json.complete}"
        else
          @robot.logger.warn "Got funny response from basecamp: #{Util.inspect json}"
      catch e
        @robot.logger.error "Error parsing basecamp response JSON: #{e}"
        return
      
      
module.exports = (robot) ->
  new GithubBasecampTodos(robot)


  
