require 'method_profiler'
RSpec::Support.require_rspec_core "formatters/base_text_formatter"

class ProfilingFormatter < RSpec::Core::Formatters::ProgressFormatter
  RSpec::Core::Formatters.register self, :start, :example_group_started, :dump_summary

  def start(*args)
    super
    @profiled = {}
  end

  def example_group_started(notification)
    super
    klass = notification.group.described_class
    if klass.is_a?(Class) && ! @profiled.keys.include?(klass)
      @profiled[klass] = MethodProfiler.observe(klass)
    end
  end

  def dump_summary(*args)
    super
    @profiled.each do |klass, profiler|
      output.puts
      output.puts profiler.report
    end
  end
end
