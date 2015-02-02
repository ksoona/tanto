def iptables_parse(iptables_output)
  chains = Hash.new
  cur_chain = nil
  cur_chain_policy = nil
  parser_state = :expecting_chain_def

  iptables_output.split("\n").each do |line|
    line.strip!
    if /^Chain /.match(line)
      assert_equal(:expecting_chain_def, parser_state)
      m = /^Chain (.+) \(policy (.+) \d+ packets, \d+ bytes\)$/.match(line)
      if m.nil?
        m = /^Chain (.+) \(\d+ references\)$/.match(line)
      end
      assert_not_nil m
      _, cur_chain, cur_chain_policy = m.to_a
      chains[cur_chain] = {
        "policy" => cur_chain_policy,
        "rules" => Array.new
      }
      parser_state = :expecting_col_descs
    elsif /^pkts\s/.match(line)
      assert_equal(:expecting_col_descs, parser_state)
      assert_equal(["pkts", "bytes", "target", "prot", "opt",
                    "in", "out", "source", "destination"],
                   line.split(/\s+/))
      parser_state = :expecting_rule_or_empty
    elsif line.empty?
      assert_equal(:expecting_rule_or_empty, parser_state)
      cur_chain = nil
      parser_state = :expecting_chain_def
    else
      assert_equal(:expecting_rule_or_empty, parser_state)
      _, _, target, prot, opt, in_iface, out_iface, source, destination, extra =
        line.split(/\s+/, 10)
      [target, prot, opt, in_iface, out_iface, source, destination].each do |var|
        assert_not_empty(var)
        assert_not_nil(var)
      end
      chains[cur_chain]["rules"] << {
        "rule" => line,
        "target" => target,
        "protocol" => prot,
        "opt" => opt,
        "in_iface" => in_iface,
        "out_iface" => out_iface,
        "source" => source,
        "destination" => destination,
        "extra" => extra
      }
    end
  end
  assert_equal(:expecting_rule_or_empty, parser_state)
  return chains
end

Then /^the firewall's policy is to (.+) all IPv4 traffic$/ do |expected_policy|
  next if @skip_steps_while_restoring_background
  expected_policy.upcase!
  iptables_output = @vm.execute_successfully("iptables -L -n -v").stdout
  chains = iptables_parse(iptables_output)
  ["INPUT", "FORWARD", "OUTPUT"].each do |chain_name|
    policy = chains[chain_name]["policy"]
    assert_equal(expected_policy, policy,
                 "Chain #{chain_name} has unexpected policy #{policy}")
  end
end

Then /^the firewall is configured to only allow the (.+) users? to connect directly to the Internet over IPv4$/ do |users_str|
  next if @skip_steps_while_restoring_background
  users = users_str.split(/, | and /)
  expected_uids = Set.new
  users.each do |user|
    expected_uids << @vm.execute_successfully("id -u #{user}").stdout.to_i
  end
  iptables_output = @vm.execute_successfully("iptables -L -n -v").stdout
  chains = iptables_parse(iptables_output)
  allowed_output = chains["OUTPUT"]["rules"].find_all do |rule|
    !(["DROP", "REJECT", "LOG"].include? rule["target"]) &&
      rule["out_iface"] != "lo"
  end
  uids = Set.new
  allowed_output.each do |rule|
    case rule["target"]
    when "ACCEPT"
      expected_destination = "0.0.0.0/0"
      assert_equal(expected_destination, rule["destination"],
                   "The following rule has an unexpected destination:\n" +
                   rule["rule"])
      next if rule["extra"] == "state RELATED,ESTABLISHED"
      m = /owner UID match (\d+)/.match(rule["extra"])
      assert_not_nil(m)
      uid = m[1].to_i
      uids << uid
      assert(expected_uids.include?(uid),
             "The following rule allows uid #{uid} to access the network, " \
             "but we only expect uids #{expected_uids} (#{users_str}) to " \
             "have such access:\n#{rule["rule"]}")
    when "lan"
      lan_subnets = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      assert(lan_subnets.include?(rule["destination"]),
             "The following lan-targeted rule's destination is " \
             "#{rule["destination"]} which may not be a private subnet:\n" +
             rule["rule"])
    else
      raise "Unexpected iptables OUTPUT chain rule:\n#{rule["rule"]}"
    end
  end
  uids_not_found = expected_uids - uids
  assert(uids_not_found.empty?,
         "Couldn't find rules allowing uids #{uids_not_found.to_a.to_s} " \
         "access to the network")
end

Then /^the firewall's NAT rules only redirect traffic for Tor's TransPort and DNSPort$/ do
  next if @skip_steps_while_restoring_background
  iptables_nat_output = @vm.execute_successfully("iptables -t nat -L -n -v").stdout
  chains = iptables_parse(iptables_nat_output)
  chains.each_pair do |name, chain|
    rules = chain["rules"]
    if name == "OUTPUT"
      good_rules = rules.find_all do |rule|
        rule["target"] == "REDIRECT" &&
          (
           rule["extra"] == "redir ports 9040" ||
           rule["extra"] == "udp dpt:53 redir ports 5353"
          )
      end
      assert_equal(rules, good_rules,
                   "The NAT table's OUTPUT chain contains some unexptected " \
                   "rules:\n" +
                   ((rules - good_rules).map { |r| r["rule"] }).join("\n"))
    else
      assert(rules.empty?,
             "The NAT table contains unexpected rules for the #{name} " \
             "chain:\n" + (rules.map { |r| r["rule"] }).join("\n"))
    end
  end
end

Then /^the firewall is configured to block all IPv6 traffic$/ do
  next if @skip_steps_while_restoring_background
  expected_policy = "DROP"
  ip6tables_output = @vm.execute_successfully("ip6tables -L -n -v").stdout
  chains = iptables_parse(ip6tables_output)
  chains.each_pair do |name, chain|
    policy = chain["policy"]
    assert_equal(expected_policy, policy,
                 "The IPv6 #{name} chain has policy #{policy} but we " \
                 "expected #{expected_policy}")
    rules = chain["rules"]
    bad_rules = rules.find_all do |rule|
      !["DROP", "REJECT", "LOG"].include?(rule["target"])
    end
    assert(bad_rules.empty?,
           "The NAT table's OUTPUT chain contains some unexptected rules:\n" +
           (bad_rules.map { |r| r["rule"] }).join("\n"))
  end
end
