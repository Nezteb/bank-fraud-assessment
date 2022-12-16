defmodule FraudChecker do
  import FraudChecker.Utils
  require Logger

  def check do
    {:ok, bank_links} = load_json_file_to_map("third-party-banks.json")
    {:ok, mercury_customers} = load_json_file_to_map("mercury-customers.json")
    {:ok, nicknames_content} = File.read("extra-questions/nicknames.txt")

    nicknames =
      nicknames_content |> String.split("\n") |> Enum.map(fn l -> String.split(l, ",") end)

    {matches, mismatches} =
      Enum.reduce(bank_links, {0, 0}, fn bank_link, acc ->
        link_id = bank_link["linkId"]
        company_id = bank_link["companyId"]
        customer = mercury_customers |> Enum.find(fn c -> c["companyId"] == company_id end)
        customer_trade_name = customer["tradeName"] |> sanitize_string([".", ",", "-", "'"])
        customer_legal_name = customer["legalName"] |> sanitize_string([".", ",", "-", "'"])
        customer_email = customer["contactEmail"]
        customer_phone = customer["contactPhoneNumber"]

        link_names =
          bank_link["names"]
          |> Enum.map(fn name -> sanitize_string(name, [".", ",", "-", "'"]) end)

        link_emails = bank_link["emails"]

        link_phones =
          bank_link["phoneNumbers"]
          |> Enum.map(fn phone -> sanitize_string(phone, [" ", "-", "(", ")", "."]) end)

        # TODO: Since input data only has one user per customer, we'll only check first user (for time)
        %{
          "firstName" => customer_user_first,
          "lastName" => customer_user_last,
          "email" => customer_user_email
        } = customer["users"] |> Enum.at(0)

        customer_user_first = sanitize_string(customer_user_first, [".", ",", "-", "'"])

        customer_user_name =
          Enum.join([customer_user_first, customer_user_last], " ")
          |> sanitize_string([".", ",", "-", "'"])

        # TODO: With more time, ideally we'd build a proper name parser that accounts for middle names, titles, etc.
        # If there are no names on the link, do not assume a name match
        name_match =
          Enum.any?(link_names, fn link_name ->
            # TODO: This will be slow, should fix later (for time)
            alternative_names =
              Enum.find(nicknames, fn nicknames -> Enum.member?(nicknames, link_name) end)

            if alternative_names != nil do
              Logger.info("Alt names for '#{link_name}': #{inspect(alternative_names)}")
            end

            strings_match?(link_name, customer_user_name) or
              strings_match?(link_name, customer_trade_name) or
              strings_match?(link_name, customer_legal_name)
          end)

        # If there are no emails on the link, label as match
        email_match =
          Enum.empty?(link_emails) or
            Enum.any?(link_emails, fn link_email ->
              link_email == customer_user_email or link_email == customer_email
            end)

        # If there are no phone numbers on the link, label as match
        phone_match =
          Enum.empty?(link_phones) or
            Enum.any?(link_phones, fn link_phone ->
              link_phone == customer_phone
            end)

        matches = %{
          name_match: name_match,
          email_match: email_match,
          phone_match: phone_match
        }

        # TODO: Should probably set up a simple state machine or rules engine for determining overall match
        overall_match =
          case matches do
            %{name_match: true} -> true
            %{name_match: false, email_match: true, phone_match: true} -> true
            _ -> false
          end

        message = """
        Link ID: #{link_id}
        Overall match: #{overall_match}
        Matches: #{inspect(matches)}
        Notes: (#{bank_link["mercuryFraudTeamComments"]})
        ---
        """

        {matches, mismatches} = acc

        if overall_match do
          Logger.info(message, ansi_color: :green)
          {matches + 1, mismatches}
        else
          Logger.warn(message)
          {matches, mismatches + 1}
        end
      end)

    Logger.info("Matches: #{matches}, mismatches: #{mismatches}", ansi_color: :cyan)
  end
end
