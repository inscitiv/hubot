# Description:
#   Relays http requests from web hooks to your dev environment.
#
# Dependencies:
#   underscore: 1.4.x
#
# Configuration:
#   None
#
# Commands:
#   hubot relay on <url> - start relaying http requests to url
#   hubot relay off [url] - stop relaying http requests
#   hubot relay list - list relay urls
#   hubot relay errors - show recent errors
#   hubot relay clear errors - clear error history
# Notes:
#   None
#

Url = require 'url'
Util = require 'util'
_ = require 'underscore'
Http = require 'http'
Https = require 'https'

Protocols =
  'https:': Https
  'http:': Http

createRequest = (options, callback) ->
  options = parseUrl(options) if 'string' is typeof options
  Protocols[options.protocol].request(options, callback)

parseUrl = (url) ->
  return url unless typeof url is 'string'
  url = "http://#{url}" unless /^http(s?):\/\/.*/.test url
  parsed = Url.parse url
  parsed.https = 'https:' is parsed.protocol
  parsed.port ?= {'https:': 443, 'http:': 80}[parsed.protocol]
  parsed

class Relay
  constructor: (@robot) ->
    @urls = {}
    @errors = []
    @robot.brain.once 'loaded', @brainLoaded

    @robot.respond /relay on (\S+)/i, @enableRelay
    @robot.respond /relay off/i, @disableRelay
    @robot.respond /relay info/i, @showRelay

    @robot.router.use @relayRequest
    # hack: make this the first middleware so it's always called
    @robot.router.stack.unshift @robot.router.stack.pop()

  brainLoaded: (data) =>
    relayData = data.relay ||= {}
    @url = relayData.url


  relayRequest: (req, res, next) =>
    {url} = @
    return next() unless url 
    options = _.extend {}, url,
      method: req.method
      path: req.url
      headers: @relayHeaders req.headers, url

    callback = (fwdres) =>
      @robot.logger.debug "got relay response #{fwdres.statusCode} from #{url.href}"
      @robot.logger.debug "headers: #{Util.format fwdres.headers}"

    onerror = (error) =>
      @robot.logger.error "error in relay to #{url.href}: #{error}"

    fwd = createRequest(options, callback)
    req.on 'end', -> fwd.end()
    req.on 'error', onerror
    fwd.on 'error', onerror
    req.on 'data', (chunk) -> fwd.write(chunk)
    req.resume()
    next()

  relayHeaders: (originalHeaders, destUrl) =>
    headers = _.clone originalHeaders
    headers.host = destUrl.hostname
    headers

  enableRelay: (msg) =>
    @url = parseUrl msg.match[1]
    @robot.brain.data.relay.url = @url
    @robot.brain.save()
    msg.send "relaying requests to #{@url.href}"

  disableRelay: (msg) =>
    @url = null
    @robot.brain.data.relay.url = null
    @robot.brain.save()
    @msg.send "relay is off"

  showRelay: (msg) =>
    if @url
      msg.send "relaying requests to #{@url.href}"
    else
      msg.send "relay is off"

module.exports = (robot) ->
  new Relay(robot)


