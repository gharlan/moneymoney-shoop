--
-- MoneyMoney Web Banking extension
-- http://moneymoney-app.com/api/webbanking
--
--
-- The MIT License (MIT)
--
-- Copyright (c) Gregor Harlan
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
--
-- Get balance and transactions for Shoop
--

WebBanking {
    version     = 1.03,
    country     = "de",
    url         = "https://www.shoop.de",
    services    = {"Shoop"},
    description = string.format(MM.localizeText("Get balance and transactions for %s"), "Shoop")
}

local function strToDate(str)
    local y, m, d = string.match(str, "(%d%d%d%d)-(%d%d)-(%d%d)")
    if d and m and y then
        return os.time { year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }
    end
end

local api = "https://api.shoop.de/api"
local connection
local token

function SupportsBank (protocol, bankCode)
    return bankCode == "Shoop" and protocol == ProtocolWebBanking
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
    connection = Connection()
    connection.language = "de-de"

    local response = JSON(connection:post(
        api .. '/auth/',
        '{"username":"' .. username .. '","password":"' .. password .. '"}',
        'application/json',
        { Accept = 'application/json' }
    )):dictionary()

    if response.result ~= "success" then
        return LoginFailed
    end

    token = response.message.token

    print("Login successful.")
end

function ListAccounts (knownAccounts)
    local response = JSON(connection:request(
        'GET',
        api .. '/user/',
        '',
        'application/json',
        { Accept = 'application/json', token = token }
    )):dictionary()

    local account = {
        name = "Shoop",
        owner = response.message.name,
        accountNumber = response.message.username,
        currency = "EUR",
        type = AccountTypeUnknown
    }
    return {account}
end

function RefreshAccount (account, since)
    local response = JSON(connection:request(
        'GET',
        api .. '/user/',
        '',
        'application/json',
        { Accept = 'application/json', token = token }
    )):dictionary()

    local balance = response.message.transactions.recieved
    local pendingBalance = response.message.transactions.pending

    local transactions = {}

    local response = JSON(connection:request(
        'GET',
        api .. '/user/transactions/?from=2014-01-01T00:00:00.000Z',
        '',
        'application/json',
        { Accept = 'application/json', token = token }
    )):dictionary()

    for i, row in ipairs(response.message) do
        if row.status ~= "blocked" and row.status ~= "reminder" then
            local transaction = {
                bookingDate = strToDate(row.tracked),
                valueDate   = strToDate(row.tracked),
                name        = row.merchant.name,
                amount      = row.cashback,
                currency    = "EUR",
                booked      = row.status == "received" or row.status == "paid",
                purpose     = row.notes
            }
            table.insert(transactions, transaction)
        end
    end

    local response = JSON(connection:request(
        'GET',
        api .. '/user/payouts/?from=2014-01-01T00:00:00.000Z',
        '',
        'application/json',
        { Accept = 'application/json', token = token }
    )):dictionary()

    for i, month in ipairs(response.message) do
        for i, row in ipairs(month.payments) do
            if row.status ~= "blocked" then
                local transaction = {
                    bookingDate = strToDate(row.date),
                    valueDate   = strToDate(row.started),
                    name        = "Auszahlung",
                    amount      = -row.amount,
                    currency    = "EUR",
                    booked      = true,
                    purpose     = row.method
                }
                table.insert(transactions, transaction)
            end
        end
    end

    return {
        balance = balance,
        pendingBalance = pendingBalance,
        transactions = transactions
    }
end

function EndSession ()
    connection:request(
        'DELETE',
        api .. '/auth/',
        '',
        'application/json',
        { Accept = 'application/json', token = token }
    )

    print("Logout successful.")
end
