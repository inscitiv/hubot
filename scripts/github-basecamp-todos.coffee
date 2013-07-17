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

gitio = (robot, commitUrl, cb) ->
  robot.http('http://git.io/')
     .header('Content-Type', 'application/x-www-form-urlencoded')
     .post("url=#{commitUrl}") (err, res, body) ->
        gitio = res.headers.location
        if err or res.statusCode >= 400
          return cb(err or new Error("HTTP error #{res.statusCode}"))
        cb(null, gitio)

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
    @payload = JSON.parse @payload
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
    _.each @todoIds, (todo) =>
      @closeTodo todo.todoId, (err, res) =>
        if err
          @robot.logger.error("Closing todo #{todo.todoId}: #{err}") 
          @robot.logger.error(err)
        else
          @todoClosed todo, res

  spam: (text, room) =>
    if arguments.length < 2
      rooms = process.env.HUBOT_TODO_ROOMS?.split(',')
      if not rooms? or rooms.length == 0
        rooms = ["Shell"]
      
      rooms.forEach (room) =>
        @spam(text, room)
    else
      @robot.logger.debug("saying \"#{text}\" in #{room}")
      user = {room : room}
      @robot.send user, text

  processCommit: (commit) =>
    hot = /BC#(\d+)/ig
    branch = @payload.ref.replace(/refs\/heads\/?/, '')
    if (msg = commit.message)?
      while (match = hot.exec(msg))? and (branch is "master" or branch is "integration")
        @todoIds.push {commit:commit, todoId:match[1]}
  
  todoClosed: (todo, todoInfo) =>
    {todoId, commit} = todo
    gitio @robot, commit.url, (err, url) =>
      if err
        return @robot.logger.error("gitio failed #{err}, #{commit}")
      message = "Commit #{url} by #{commit.author.name} closed todo\n
\t#{todoInfo.content}\n
\t#{todoInfo.url}" 

      todo.body = todoInfo
      todo.gitio = url
      @addComment todo, (err)=>
        unless err
          @spam(message)

  addComment: (todo, cb) =>
    cb ?= ->
    sep = "\n\t" #???
    comment = 
      content: "Closed by #{todo.gitio}<br/>
      <pre>* #{todo.commit.author.name} - #{todo.commit.message}</pre>"

    @robot.http(@todoCommmentUrl(todo.todoId))
      .auth(process.env.BASECAMP_USERNAME,process.env.BASECAMP_PASSWORD)
      .header("Content-Type", "application/json")
      .post(JSON.stringify(comment)) (err,res,body) =>
        if err
          @robot.logger.error("error adding comment")
          @robot.logger.error(err)
          cb(err)
        else if res?.statusCode >= 400
          @robot.logger.error("got status #{res.statusCode}")
          cb(new Error("HTTP status #{res.statusCode}"))
        else
          @robot.logger.debug("saved comment", body)
          cb() 

  todoCommmentUrl: (todoId) =>
    "https://basecamp.com/#{process.env.HUBOT_BASECAMP_ACCOUNT}" + 
      "/api/v1/projects/#{process.env.HUBOT_BASECAMP_PROJECT}/todos/#{todoId}/comments.json"
    

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
          cb(null, if _.isString(body) then JSON.parse(body) else body) if  _.isFunction(cb)
          @robot.logger.debug("TODO closed!")
          @robot.logger.debug(body)
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


  
