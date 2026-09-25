require_relative 'asc-request'

apply = ARGV.include?('--apply')
groups = asc_request('GET', '/v1/apps/6804307648/subscriptionGroups')['data']
groups.each do |group|
  group_id = group.fetch('id')
  localizations = asc_request('GET', "/v1/subscriptionGroups/#{group_id}/subscriptionGroupLocalizations")['data']
  if apply && localizations.none? { |row| row.dig('attributes', 'locale') == 'en-US' }
    asc_request('POST', '/v1/subscriptionGroupLocalizations', data: {
      type: 'subscriptionGroupLocalizations',
      attributes: { locale: 'en-US', name: 'Goodies Snap Plans' },
      relationships: { subscriptionGroup: { data: { type: 'subscriptionGroups', id: group_id } } }
    })
  end
  subs = asc_request('GET', "/v1/subscriptionGroups/#{group_id}/subscriptions")['data']
  subs.each do |sub|
    id = sub.fetch('id')
    attrs = sub.fetch('attributes')
    pro = attrs.fetch('productId').include?('.pro.')
    yearly = attrs.fetch('subscriptionPeriod') == 'ONE_YEAR'
    name = "#{pro ? 'Pro' : 'Plus'} #{yearly ? 'Yearly' : 'Monthly'}"
    description = pro ? '400 AI actions each month, including dish scanning.' : '100 AI actions each month for recipe imports.'
    if apply
      asc_request('PATCH', "/v1/subscriptions/#{id}", data: {
        type: 'subscriptions', id: id,
        attributes: {
          groupLevel: pro ? 1 : 2,
          reviewNote: "Open Profile, then upgrade to view #{name}. Includes #{pro ? 400 : 100} AI actions per calendar month. #{pro ? 'Camera dish scanning is included.' : 'Imports from links and text are included; camera scanning requires Pro.'} Restore Purchases is on the paywall. No local trial or top-up purchases are offered."
        }
      })
    end
    rows = asc_request('GET', "/v1/subscriptions/#{id}/subscriptionLocalizations")['data']
    existing = rows.find { |row| row.dig('attributes', 'locale') == 'en-US' }
    if apply
      if existing
        asc_request('PATCH', "/v1/subscriptionLocalizations/#{existing['id']}", data: {
          type: 'subscriptionLocalizations', id: existing['id'], attributes: { name: name, description: description }
        })
      else
        asc_request('POST', '/v1/subscriptionLocalizations', data: {
          type: 'subscriptionLocalizations', attributes: { locale: 'en-US', name: name, description: description },
          relationships: { subscription: { data: { type: 'subscriptions', id: id } } }
        })
      end
    end
    prices = asc_request('GET', "/v1/subscriptions/#{id}/prices?limit=1")
    screenshot = asc_request('GET', "/v1/subscriptions/#{id}/appStoreReviewScreenshot")
    puts JSON.generate(name: name, id: id, state: attrs['state'], level: attrs['groupLevel'], localizations: rows.map { |r| r['attributes'] }, prices: prices.dig('meta', 'paging', 'total') || prices['data'].length, screenshot: screenshot['data'])
  end
end
