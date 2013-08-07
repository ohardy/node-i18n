_s        = require 'underscore.string'
_         = require 'lodash'
fs        = require 'fs'
# util      = require 'util'
path      = require 'path'
{sprintf} = require 'sprintf'
Router    = require 'erouter'

directory      = "./locales"

debug = false

options =
  locales:        {}
  defaultLocale:  "en"
  updateFiles:    true
  verbose:        true

module.exports = exports = i18n = {}

class Phrase
  constructor: (singular, plural, none, count, args, locale) ->
    @singular = singular
    @plural   = plural
    @none     = none
    @count    = count
    @args     = args
    @locale   = locale
  toString: ->
    'toto'

setOptionBool = (name, value) ->
  options[name] = value if typeof value is 'boolean'

setOptionString = (name, value) ->
  options[name] = value if typeof value is 'string'

setOptionArray = (name, value) ->
  options[name] = value if value instanceof Array

i18n.configure = (options) ->
  for elt in ['updateFiles', 'verbose']
    setOptionBool elt, options[elt]

  for elt in ['defaultLocale']
    setOptionString elt, options[elt]

  for elt in ['locales']
    setOptionArray elt, options[elt]

  for locale in options.locales
    read locale

i18n.singular = (phrase, args, locale) ->
  msg = translate locale, phrase
  msg ?= phrase
  sprintf msg, args

i18n.plural = (singular, plural, none, count, args, locale) ->
  count = parseInt(count, 10)
  msg = translate locale, phrase
  msg ?= phrase
  if count <= 0
    msg = msg.none
  else if count is 1
    msg = msg.other
  else
    msg = msg.one

  args.count = count
  msg = sprintf msg, args

i18n.i18nUrl = (url, locale) ->
  _orig = url
  url = i18n.singular url, {}, locale
  url._orig = _orig
  # console.log 'i18nUrl : ', url, url._orig
  url

i18n.urlFor = (url, obj, locale) ->
  url = i18n.i18nUrl url, locale
  url = url.replace /(\/:\w+\??)/g, (url, c) ->
    c = c.replace(/[/:?]/g, "")
    (if obj[c] then "/" + obj[c] else "")
  "/#{locale}#{url}"

singularFor = (request) ->
  (phrase, args) ->
    # console.log 'singular exec : ', phrase, ' for : ', request.locale
    i18n.singular phrase, args, request.locale

pluralFor = (request) ->
  (singular, plural, none, count, args) ->
    i18n.plural singular, plural, none, count, args, request.locale

urlForFor = (request) ->
  (url, args, locale = request.locale) ->
    i18n.urlFor url, args, locale

lurlForFor = (request) ->
  (url, locale) ->
    i18n.urlFor url, null, locale

i18n.expressBind = (app, opts) ->
  router = new Router app
  # console.log ' router : ', router
  # router.on 'add-route', (route) ->
  #   console.log 'added route :', route.method, route.path
  #   if route.path._orig?
  #     console.log 'Orig : ', route.path._orig
  app._router = router

  app.use i18n.express opts

i18n.express = (opts = {}) ->
  options.guessLocale = true

  regexp1 = new RegExp("^/(" + options.locales.join('|') + ")$")
  regexp2 = new RegExp("^/(" + options.locales.join('|') + ")/")

  (req, res, next) ->
    req.__s     = singularFor req
    req.__p     = pluralFor req
    req.urlFor  = urlForFor req
    req.lurlFor = lurlForFor req

    res.locals.__s     = req.__s
    res.locals.__i     = req.__s
    res.locals.__p     = req.__p
    res.locals.urlFor  = req.urlFor
    res.locals.lurlFor = req.lurlFor
    res.locals.req     = req

    delete req._parsedUrl

    match = req.url.match(regexp1) or req.url.match(regexp2)

    if match
      l = match[1]
      i18n.setLocale req, l
      req.url = req.url.slice(l.length + 1)

    if not req.locale?
      i18n.guessLocale req
      newUrl = req.url
      unless _s.startsWith(newUrl, '/')
        newUrl = "/#{newUrl}"
      res.redirect urlForFor(req)(newUrl)
    else
      next()

i18n.setLocale = (arg1, arg2) ->
  request = `undefined`
  targetLocale = arg1
  if arg2 and options.locales[arg2]
    request = arg1
    targetLocale = arg2
  if options.locales[targetLocale]
    if not request?
      options.currentLocale = targetLocale
    else
      request.locale = targetLocale

  i18n.getLocale request

i18n.getLocale = (req) ->
  return options.currentLocale if not req?
  if debug
    console.log 'getLocale for : ', req.url, req.locale
  req.locale

i18n.guessLocale = (request) ->
  if typeof request is "object"
    languages = []
    regions   = []

    languageHeader = request.headers["accept-language"]

    for elt in ['languages', 'regions']
      request[elt] = [options.defaultLocale]

    for elt in ['language', 'region']
      request[elt] = options.defaultLocale

    if languageHeader
      languageHeader.split(",").forEach (language) ->
        header = language.split(";", 1)[0]
        lr     = header.split("-", 2)
        languages.push lr[0].toLowerCase()  if lr[0]
        regions.push   lr[1].toLowerCase()  if lr[1]

      if languages.length > 0
        request.languages = languages
        request.language  = languages[0]
      if regions.length > 0
        request.regions = regions
        request.region  = regions[0]

    # setting the language by cookie
    # request.language = request.cookies[cookiename]  if cookiename and request.cookies[cookiename]
    i18n.setLocale request, request.language

translate = (locale, singular, plural, none) ->
  if not locale?
    locale = options.defaultLocale
  read locale  unless options.locales[locale]
  setForLocales singular, plural, none
  options.locales[locale][singular]

setForLocales = (singular, plural, none) ->
  if debug
    console.log 'setForLocales : ', singular, plural, none
  for locale in options.locales
    if plural
      unless options.locales[locale][singular]
        options.locales[locale][singular] =
          one: singular
          other: plural
          none: none

        write locale
    else
      unless options.locales[locale][singular]
        options.locales[locale][singular] = singular
      write locale

read = (locale) ->
  if locale?
    localeFile = {}
    file       = locate locale

    try
      if debug
        console.log "read " + file + " for locale: " + locale  if options.verbose
      localeFile = fs.readFileSync(file)
      try

        # parsing filecontents to locales[locale]
        options.locales[locale] = JSON.parse(localeFile)
      catch e
        console.error "unable to parse locales from file (maybe " + file + " is empty or invalid json?): ", e
    catch e
      console.error e
      # unable to read, so intialize that file
      # locales[locale] are already set in memory, so no extra read required
      # or locales[locale] are empty, which initializes an empty locale.json file
      console.log "initializing " + file  if options.verbose
      write locale, true

write = (locale, dontRead = false) ->
  # don't write new locale information to disk if updateFiles isn't true
  savedLocale = options.locales[locale] ?= {}
  unless dontRead
    read locale
    _.merge(savedLocale, options.locales[locale])
    options.locales[locale] = savedLocale

  return  unless options.updateFiles

  # creating directory if necessary
  try
    stats = fs.lstatSync directory
  catch e
    if debug
      console.log "creating locales dir in: #{directory}"  if debug
    fs.mkdirSync directory, 0o0755

  # writing to tmp and rename on success
  try
    target = locate locale
    tmp    = target + ".tmp"
    fs.writeFileSync tmp, JSON.stringify(options.locales[locale], null, "\t"), "utf8"
    Stats = fs.statSync(tmp)
    if Stats.isFile()
      fs.renameSync tmp, target
    else
      console.error "unable to write locales to file (either " + tmp + " or " + target + " are not writeable?): ", e
  catch e
    console.error "unexpected error writing files (either " + tmp + " or " + target + " are not writeable?): ", e

locate = (locale) ->
  path.normalize "#{directory}/#{locale}.js"
