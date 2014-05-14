config = require './config'

mAccount = require './model/account'

exports.calcBilling = (account, callback) ->
  amount = 0

  for planName in account.attribute.plans
    plan = config.plans[planName]

    price = plan.price / 30 / 24
    time = (Date.now() - account.attribute.last_billing.getTime()) / 1000 / 3600
    time = Math.ceil time
    amount += price * time

  modifier =
    'attribute.last_billing': new Date()
    $inc:
      'attribute.balance': amount

  if (not account.attribute.arrears_at) and account.attribute.balance < 0
    modifier['attribute.arrears_at'] = new Date()

  mAccount.update _id: account._id, modifier, {}, ->
    mAccount.findId account._id, (account) ->
      callback account