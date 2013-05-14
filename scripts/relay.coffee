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
		@robot.respond /relay off(?: (\S+))?/i, @disableRelay
		@robot.respond /relay list/i, @listRelays
		@robot.respond /relay errors/i, @showErrors
		@robot.respond /relay clear errors/i, @clearErrors

		@robot.router.use @relayRequest
		# hack: make this the first middleware so it's always called
		@robot.router.stack.unshift @robot.router.stack.pop()



	brainLoaded: (data) =>
		relayData = data.relay ||= {}
		@urls = relayData.urls ||= {}
		@errors = relayData.errors ||= []


	relayRequest: (req, res, next)=>
		try
			@doRelayRequest.apply @, arguments
		finally
			next() if typeof next is 'function'

	doRelayRequest: (req, res, next) ->
		for href, url of @urls
			@relayRequestTo(url, req, res)

	relayRequestTo: (url, req, res) ->
		options = _.extend {}, url,
			method: req.method
			path: req.url
			headers: _.clone req.headers

		onresponse = (response) =>
			code = response.statusCode
			full = "#{url.href + req.url.substr(1)} responded #{code} #{Http.STATUS_CODES[code]}"
			@robot.logger.info full
			if code != 200 then @addError full

		onerror = (error) =>
			@robot.logger.error "relay error: #{error}"
			@addError(error)

		onend = =>
			relayed.end()

		@robot.logger.debug "relaying request #{options.method} #{options.path} to #{url.href}"
		relayed = createRequest options, onresponse

		relayed.once 'error', onerror
		req.once 'error', onerror
		req.once 'end', onend

		req.pipe relayed
		req.resume()

	listRelays: (msg) =>
		hrefs = Object.keys @urls
		if hrefs.length == 0
			msg.send "No relays are enabled"
		else
			resp = ["Relaying requests to the following hosts:"]
			hrefs.forEach (href) ->
				resp.push "\t#{href}"
			msg.send resp.join "\n"


	enableRelay: (msg) =>
		url = parseUrl msg.match[1]
		if url.href in @urls
			msg.send("Relay to #{url.href} is already enabled")
		else
			@urls[url.href] = url
			msg.send("Enabled relay to #{url.href}")
		@robot.brain.save()

	disableRelay: (msg) =>
		if msg.match[1]?
			url = parseUrl msg.match[1]
			if @urls[url.href]?
				delete @urls[url.href]
				msg.send "Disabled relay to #{url.href}"
			else
				msg.send "Relay to #{url.href} is not enabled"
		else
			keys = Object.keys @urls
			if keys.length == 0
				msg.send "No relays are enabled"
			else
				reply = ["Disabled the following relays:"]
				keys.forEach (href) =>
					delete @urls[href]
					reply.push("\t#{href}")
				msg.send reply.join("\n")
		@robot.brain.save()

	showErrors: (msg) =>
		reply = ["Relay errors:"]
		@errors.forEach (err) ->
			reply.push "\t#{err.what} at #{err.when}"
		msg.send reply.join "\n"

	clearErrors: (msg) =>
		reply = "Relay deleted #{@errors.length} errors"
		@errors.length = 0
		@robot.brain.save()
		msg.send reply

	addError: (err) =>
		err ?= "Unknown Error WTF!"
		@errors.push {what: err.toString(), when: new Date().toString()}
		if @errors.length >= process.env.HUBOT_RELAY_MAX_ERRORS ? 20
			@errors.shift()
		@robot.brain.save()

module.exports = (robot) ->
	new Relay(robot)


