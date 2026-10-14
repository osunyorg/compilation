# Mises en forme communes au log et aux pages
module Formats
  module_function

  def format_time(time)
    time.strftime('%d/%m/%Y %H:%M:%S %Z')
  end

  def format_duration(seconds)
    minutes, seconds = seconds.round.divmod(60)
    minutes.zero? ? "#{seconds} s" : "#{minutes} min #{seconds} s"
  end

  # Base 1024, comme df -h : au Mo près en dessous de 1 Go, au dixième de Go au-delà
  def format_size(bytes)
    megabytes = bytes / 1024.0**2
    return "#{megabytes.round} Mo" if megabytes.round < 1024
    "#{(megabytes / 1024).round(1).to_s.tr('.', ',')} Go"
  end
end
