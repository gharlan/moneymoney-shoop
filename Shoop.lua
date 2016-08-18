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
    version     = 1.00,
    country     = "de",
    url         = "https://www.shoop.de",
    services    = {"Shoop"},
    description = string.format(MM.localizeText("Get balance and transactions for %s"), "Shoop")
}

local function strToNumber(str)
    str = string.gsub(str, "€", "")
    str = string.gsub(str, "[^,%d]", "")
    str = string.gsub(str, ",", ".")
    return tonumber(str)
end

local function strToDate(str)
    local y, m, d = string.match(str, "(%d%d%d%d)-(%d%d)-(%d%d)")
    if d and m and y then
        return os.time { year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }
    end
end

local function strToDate2(str)
    local y, m, d = string.match(str, "(%d%d)(%d%d)(%d%d)")
    if d and m and y then
        return os.time { year = 2000 + y, month = m, day = d, hour = 0, min = 0, sec = 0 }
    end
end

local function parseCSV (csv, row)
    csv = csv .. "\n"
    local len    = string.len(csv)
    local cols   = {}
    local field  = ""
    local quoted = false
    local start  = false

    local i = 1
    while i <= len do
        local c = string.sub(csv, i, i)
        if quoted then
            if c == '"' then
                if i + 1 <= len and string.sub(csv, i + 1, i + 1) == '"' then
                    -- Escaped quotation mark.
                    field = field .. c
                    i = i + 1
                else
                    -- End of quotaton.
                    quoted = false
                end
            else
                field = field .. c
            end
        else
            if start and c == '"' then
                -- Begin of quotation.
                quoted = true
            elseif c == ";" then
                -- Field separator.
                table.insert(cols, field)
                field  = ""
                start  = true
            elseif c == "\r" then
                -- Ignore carriage return.
            elseif c == "\n" then
                -- New line. Call callback function.
                table.insert(cols, field)
                row(cols)
                cols   = {}
                field  = ""
                quoted = false
                start  = true
            else
                field = field .. c
            end
        end
        i = i + 1
    end
end

local connection
local myPage

function SupportsBank (protocol, bankCode)
    return bankCode == "Shoop" and protocol == ProtocolWebBanking
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
    connection = Connection()
    connection.language = "de-de"

    local response = HTML(connection:get(url))
    response:xpath("//input[@name='username']"):attr("value", username)
    response:xpath("//input[@name='password']"):attr("value", password)

    response = HTML(connection:request(response:xpath("//button[@id='login_email']"):click()))
    if response:xpath("//[@id='loginmodal']/[@class='guide_warn']"):length() > 0 then
        print("Response: " .. response:xpath("//[@id='loginmodal']/[@class='guide_warn']"):text())
        return LoginFailed
    end

    print("Login successful.")
    myPage = response
end

function ListAccounts (knownAccounts)
    local response = HTML(connection:get("https://www.shoop.de/my/settings.php"))

    local username = response:xpath("//span[@class='username']"):text()
    local owner = response:xpath("//input[@id='name']"):val()
    if not owner or #owner == 0 then
        owner = username
    end

    local account = {
        name = "Shoop",
        owner = owner,
        accountNumber = username,
        currency = "EUR",
        type = AccountTypeUnknown
    }
    return {account}
end

function RefreshAccount (account, since)
    local balance = strToNumber(myPage:xpath("//div[@class='user-account-stat']/p[@class='amount payed']"):text())
    local pendingBalance = strToNumber(myPage:xpath("//div[@class='user-account-stat']/p[@class='amount open']"):text())

    local transactions = {}

    local csv = connection:get("https://www.shoop.de/my/transactions.php?csv=true")

    parseCSV(csv, function (fields)
        if #fields > 10 and fields[4] ~= "abgelehnt" and strToDate(fields[8]) ~= nil and strToDate(fields[8]) >= since then
            local transaction = {
                bookingDate = strToDate(fields[8]),
                valueDate   = strToDate(fields[11]),
                name        = fields[2],
                amount      = strToNumber(fields[5]),
                currency    = "EUR",
                booked      = fields[4] == "verfügbar" or fields[4] == "bezahlt"
            }
            table.insert(transactions, transaction)
        end
    end)

    local response = HTML(connection:get("https://www.shoop.de/my/payments.php"))

    response:xpath("//table[@id='balance_table']/tbody/tr[@class='type_withdraw ']"):each(function (index, row)
        local date = strToDate2(row:xpath("td[1]/div"):text())
        if date >= since then
            local transaction = {
                bookingDate = date,
                name        = "Auszahlung",
                purpose     = row:xpath("td[3]"):text(),
                amount      = tonumber(row:xpath("td[2]"):attr("data-amount")) / 100,
                currency    = "EUR",
                booked      = true
            }
            table.insert(transactions, transaction)
        end
    end)

    return {
        balance = balance,
        pendingBalance = pendingBalance,
        transactions = transactions
    }
end

function EndSession ()
    connection:get("https://www.shoop.de/login.php?logout")

    print("Logout successful.")
end
