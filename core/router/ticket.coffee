express = require 'express'
async = require 'async'
_ = require 'underscore'

{requireAuthenticate} = app.middleware
{mAccount, mTicket} = app.models
{config, notification} = app

module.exports = exports = express.Router()

loadTicket = (req, res, next) ->
  req.inject [requireAuthenticate, constructObjectID()], ->
    mTicket.findOne _id: req.body.id, (err, ticket) ->
      unless ticket
        return res.error 'ticket_not_exist'

      unless mTicket.getMember ticket, req.account
        unless 'root' in req.account.groups
          return res.error 'forbidden'

      req.ticket = ticket

      next()

exports.get '/list', requireAuthenticate, (req, res) ->
  mTicket.find
    $or: [
      account_id: req.account._id
    ,
      members: req.account._id
    ]
  ,
    sort:
      updated_at: -1
  .toArray (err, tickets) ->
    res.render 'ticket/list',
      tickets: tickets

exports.get '/create', requireAuthenticate, (req, res) ->
  res.render 'ticket/create'

exports.get '/view', loadTicket, (req, res) ->
  {ticket} = req

  async.map ticket.members, (member_id, callback) ->
    mAccount.findOne _id: member_id, callback
  , (err, result) ->
    ticket.members = result

    async.map ticket.replies, (reply, callback) ->
      mAccount.findOne _id: reply.account_id, (err, account) ->
        reply.account = account
        callback null, reply

    , (err, result) ->
      ticket.replies = result

      mAccount.findOne _id: ticket.account_id, (err, account) ->
        ticket.account = account

        console.log ticket.created_at

        res.render 'ticket/view',
          ticket: ticket

exports.post '/create', requireAuthenticate, (req, res) ->
  unless /^.+$/.test req.body.title
    return res.error 'invalid_title'

  status = if 'root' in req.account.groups then 'open' else 'pending'

  mTicket.createTicket req.account, req.body.title, req.body.content, [req.account], status, {}, (ticket) ->
    res.json
      id: ticket._id

    notification.createGroupNotice 'root', 'ticket_create',
      title: _.template(res.t('notification_title.ticket')) ticket
      body: _.template(app.template_data['ticket_create_email'])
        ticket: ticket
        account: req.account
        config: config
    , ->

exports.post '/reply', loadTicket, (req, res) ->
  {ticket} = req

  unless req.body.content
    return res.error 'invalid_content'

  status = if 'root' in req.account.groups then 'open' else 'pending'

  mTicket.createReply ticket, req.account, req.body.content, status, (reply) ->
    res.json
      id: reply._id

    async.each ticket.members, (member_id, callback) ->
      if member_id.toString() == req.account._id.toString()
        return callback()

      mAccount.findOne
        _id: member_id
      , (err, account) ->
        notification.createNotice account, 'ticket_reply',
          title: _.template(res.t('notification_title.ticket')) ticket
          body: _.template(app.template_data['ticket_reply_email'])
            ticket: ticket
            reply: reply
            account: req.account
            config: config
        , ->
          callback()
    , ->

exports.post '/update_status', loadTicket, (req, res) ->
  {ticket} = req

  if 'root' in req.account.groups
    allow_status = ['open', 'pending', 'finish', 'closed']
  else
    allow_status = ['closed']

  if req.body.status in allow_status
    if ticket.status == req.body.status
      return res.error 'already_in_status'
  else
    return res.error 'invalid_status'

  mTicket.update {_id: ticket._id},
    $set:
      status: req.body.status
  , ->
    res.json {}
