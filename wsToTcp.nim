#
#
#              Websocket to tcp proxy
#               (c) Copyright 2016 
#             David Krause, Tobias Freitag
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
## This is an asyn websocket to tcp transport,
## Atm this is capable of tunneling a line based protocol (namely IRC)
## Everything else is not tested.
## For a client to test it please have a look
## at the ch6t webclient

import asyncnet, asyncdispatch, websocket
import asynchttpserver
import os
import unicode
import strutils
import cgi

const 
  URL_ENCODE = false ## if this is enabled the data sent to ws will be "encodeUrl" data that comes back will be "decodeUrl"
                     ## this means that the websocket client has to de- and encode the url as well.
                     ## the server endpoint must not be changed
                     ## please note that this methode should NOT change payload data
                     ## http://blog.fgribreau.com/2012/05/how-to-fix-could-not-decode-text-frame.html

  FILTER_UNICODE = true ## if this is enabled the data that will be sent to the websocket 
                        ## will be stripped from unwanted unicode chars.
                        ## please note that this is CHANGEING the payload data
                        ## http://blog.fgribreau.com/2012/05/how-to-fix-could-not-decode-text-frame.html

type Host = tuple[host: string, port: Port]

proc filterUnicode(msg: var string) =
  ## this strips out unwanted unicode characters (to avoid compatibility issues with browsers)
  ## be aware that this is acually --::changeing the payload data::-- thats get sent TO the browser!
  if FILTER_UNICODE == false:
    # return msg
    discard
  else:
    while true:
      var brokenCharPos = validateUtf8(msg)
      if brokenCharPos == -1:
        # this is valid utf-8
        # return msg
        break
      else:
        echo "Deleted invalide UTF-8 char from msg at pos: " , brokenCharPos
        msg.delete(brokenCharPos, brokenCharPos)

proc pumpWsToTcp(req: Request, endpointSocket: AsyncSocket): Future[void] {.async.} =
  var fromWs: tuple[opcode: Opcode, data: string]
  while true:

    try:
      fromWs = await req.client.readData(false)
    except:
      req.client.close()
      endpointSocket.close()
      return
    echo "ws: " & fromWs.data

    if fromWs.data == "":
      raise
    
    if URL_ENCODE:
      fromWs.data = decodeUrl(fromWs.data)    
      
    try:
      await endpointSocket.send(fromWs.data)
    except:
      # break
      raise

proc pumpTcpToWs(req: Request, endpointSocket: AsyncSocket): Future[void] {.async.} =
  var fromEndpoint: string = ""
  while true:    
    try:
      fromEndpoint = await endpointSocket.recvLine()
    except:
      return

    echo "endpoint: " & fromEndpoint
    if fromEndpoint == "":
      return

    try:
      filterUnicode(fromEndpoint) # strips invalid utf-8 chars 
      if URL_ENCODE:
        fromEndpoint = encodeUrl(fromEndpoint)
        
      await req.client.sendText(fromEndpoint,false)
    except:
      echo "pumpTcpToWs client socket is fuckd"
      return

proc processClientWebsocket(req: Request, src, dst: Host, page: string) {.async.} =
  let (success, error) = await(verifyWebsocketRequest(req, "irc"))
  if not success:
    if req.url.path == "/":
      asyncCheck req.respond(Http200, readFile( page / "index.html") )
    else:  
      # echo "Deliver static page"
      let fullPath = page / req.url.path
      if fullPath.fileExists:
        asyncCheck req.respond(Http200, readFile(fullPath) )
      # asyncCheck req.respond(Http200, readFile(page) )
    req.client.close()
  else:
    echo "New websocket customer arrived!"
    var endpointSocket: AsyncSocket = newAsyncSocket()
    try:
      await endpointSocket.connect(dst.host, dst.port)
      echo "Connected to endpoint"
      asyncCheck pumpWsToTcp(req, endpointSocket)
      asyncCheck pumpTcpToWs(req, endpointSocket) 
    except:
      echo "Could not connect to endpoint :("
      asyncCheck req.client.sendText("Could not connect to endpoint :(\n",false)
      echo "Closeing ws and tcp socket after error..."

      req.client.close()
      endpointSocket.close()

proc proxy * (src, dst: Host ,page = "info.html") =
  ## Proxy line by line based protocols between ws://src and tcp://dst
  ## `page` gets read from the filesystem when connection is not websocket
  ## `page` could also be a directory, then everythin under this directory will be served from "/"
  ## TODO use src iface 
  var websocketServer = newAsyncHttpServer()
  proc paramHelper(req: Request) {.async.} = 
    try:
      asyncCheck processClientWebsocket(req, src, dst, page) 
    except:
      echo "processClientWebsocket is fuckd"
  asyncCheck websocketServer.serve(src.port, paramHelper)

when isMainModule:

  # proxy( ("0.0.0.0",Port(7787)), ("10.0.0.1",Port(6667)), page = "twirc.html" )
  # proxy( ("0.0.0.0",Port(7788)), ("irc.freenode.net",Port(6667)), page = "twirc.html" )
  # proxy( ("0.0.0.0",Port(8080)), ("127.0.0.1",Port(6667)), page = "info.html" )

  proxy(("0.0.0.0",Port(7787)), ("10.0.0.1",Port(6667)), page = "c:\\Users\\dkrause\\ch6t\\" )
  proxy(("0.0.0.0",Port(7788)), ("irc.freenode.net",Port(6667)), page = "c:\\Users\\dkrause\\ch6t\\" )
  proxy(("0.0.0.0",Port(7789)), ("127.0.0.1",Port(6667)), page = "c:\\Users\\dkrause\\ch6t\\" )

  # For the information page
  var server = newAsyncHttpServer()
  proc cb(req: Request) {.async.} =
    await req.respond(Http200, readFile("./info.html"))
  asyncCheck server.serve(Port(8080), cb)

  runForever()
  