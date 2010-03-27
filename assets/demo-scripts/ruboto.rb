#######################################################
#
# ruboto.rb (by Scott Moyer)
# 
# Wrapper for using RubotoActivity in Ruboto IRB
#
#######################################################

$RUBOTO_VERSION = 2

def confirm_ruboto_version(required_version, exact=true)
  raise "requires $RUBOTO_VERSION=#{required_version} or greater, current version #{$RUBOTO_VERSION}" if $RUBOTO_VERSION < required_version and not exact
  raise "requires $RUBOTO_VERSION=#{required_version}, current version #{$RUBOTO_VERSION}" if $RUBOTO_VERSION != required_version and exact
end

include Java
include_class "org.jruby.ruboto.RubotoActivity"
include_class "android.app.Activity"
include_class "android.content.Intent"
include_class "android.os.Bundle"
include_class "android.view.View"
include_class "android.view.ViewGroup"
include_class "android.widget.Toast"
include_class "android.widget.ListView"
include_class "android.widget.Button"
include_class "android.widget.ToggleButton"
include_class "android.widget.LinearLayout"
include_class "android.widget.EditText"
include_class "android.widget.TextView"
include_class "android.widget.TimePicker"
include_class "android.widget.DatePicker"
include_class "android.app.TimePickerDialog"
include_class "android.app.DatePickerDialog"
include_class "android.widget.Chronometer"
include_class "android.widget.TableLayout"
include_class "android.widget.TableRow"
include_class "android.widget.ArrayAdapter"
include_class "android.widget.ScrollView"
include_class "java.util.Arrays"
include_class "java.util.ArrayList"

include_class "android.R"

class R
  Layout = JavaUtilities.get_proxy_class('android.R$layout')
  Style = JavaUtilities.get_proxy_class('android.R$style')
end

class Activity
  attr_accessor :init_block

  def start_ruboto_dialog(remote_variable, &block)
    start_ruboto_activity(remote_variable, true, &block)
  end

  def start_ruboto_activity(remote_variable, dialog=false, &block)
    @@init_block = block

    if @initialized or not self.is_a?(RubotoActivity)
      b = Bundle.new
      b.putString("Remote Variable", remote_variable)
      b.putBoolean("Define Remote Variable", true)
      b.putString("Initialize Script", "#{remote_variable}.initialize_activity")

      i = Intent.new
      i.setClassName "org.jruby.ruboto.irb", 
                     "org.jruby.ruboto.Ruboto#{dialog ? 'Dialog' : 'Activity'}"
      i.putExtra("RubotoActivity Config", b)

      self.startActivity i
    else
      instance_eval "#{remote_variable}=self"
      setRemoteVariable remote_variable
      initialize_activity
      on_create nil
    end

    self
  end

  def toast(text, duration=5000)
    Toast.makeText(self, text, duration).show
  end
  
  def toast_result(result, success, failure, duration=5000)
    toast(result ? success : failure, duration)
  end
end

class View
  @@convert_params = {
     :wrap_content => ViewGroup::LayoutParams::WRAP_CONTENT,
     :fill_parent  => ViewGroup::LayoutParams::FILL_PARENT,
  }

  def configure(context, params = {})
    if width = params.delete(:width)
      getLayoutParams.width = @@convert_params[width] or width
    end

    if height = params.delete(:height)
      getLayoutParams.height = @@convert_params[height] or height
    end

    params.each do |k, v|
      self.send("set#{k.to_s.gsub(/(^|_)([a-z])/) {$2.upcase}}", v)
    end
  end
end

class ListView
  attr_reader :adapter, :adapter_list

  def configure(context, params = {})
    if params.has_key? :list
      @adapter_list = ArrayList.new
      @adapter_list.addAll(params[:list])
      @adapter = ArrayAdapter.new(context, R::Layout::simple_list_item_1, @adapter_list)
      setAdapter @adapter
      params.delete :list
    end
    setOnItemClickListener(context)
    super(context, params)
  end

  def reload_list(list)
    @adapter_list.clear();
    @adapter_list.addAll(list)
    @adapter.notifyDataSetChanged
  end
end

class Button
  def configure(context, params = {})
    setOnClickListener(context)
    super(context, params)
  end
end

class RubotoActivity
  #
  # Initialize
  #

  def initialize_activity()
    instance_eval &@@init_block 
    @initialized = true
    self
  end
  
  def on_create(bundle)
    setContentView(instance_eval &@content_view_block) if @content_view_block
  end
  
  def setup_content &block
    @content_view_block = block
  end

  #
  # Setup Callbacks
  #

  def self.create_callback(callback, parameters=[], additional_code="")
    class_eval "
      def handle_#{callback} &block
        requestCallback RubotoActivity::CB_#{callback.to_s.upcase}
        @#{callback}_block = block
      end
    
      def on_#{callback}(#{parameters.join(',')})
        #{additional_code}
        instance_eval {@#{callback}_block.call(#{parameters.join(',')})} if @#{callback}_block
      end
    "
  end

  create_callback :start
  create_callback :resume
  create_callback :restart
  create_callback :pause
  create_callback :stop
  create_callback :destroy
  create_callback :activity_result, [:intent]

  create_callback :save_instance_state, [:bundle]
  create_callback :restore_instance_state, [:bundle]
  create_callback :create_options_menu, [:menu], "@menu, @context_menu = menu, nil"
  create_callback :create_context_menu, [:menu, :view, :menu_info], "@menu, @context_menu = nil, menu"
  create_callback :item_click, [:adapter_view, :view, :pos, :item_id]
  create_callback :key, [:view, :key_code, :event]
  create_callback :editor_action, [:view, :action_id, :event]
  create_callback :click, [:view]
  create_callback :time_changed, [:view, :hour, :minute]
  create_callback :date_changed, [:view, :year, :month, :day]
  create_callback :time_set, [:view, :hour, :minute]
  create_callback :date_set, [:view, :year, :month, :day]
  create_callback :create_dialog, [:dialog_id]
  create_callback :prepare_dialog, [:dialog_id, :dialog]

  #
  # Option Menus
  #

  def add_menu title, &block
    mi = @menu.add(title)
    mi.class.class_eval {attr_accessor :on_click}
    mi.on_click = block
  end
 
  def on_menu_item_selected(num,menu_item)
    instance_eval &(menu_item.on_click) if @menu
  end

  #
  # Context Menus
  #

  def add_context_menu title, &block
    mi = @context_menu.add(title)
    mi.class.class_eval {attr_accessor :on_click}
    mi.on_click = block
  end
 
  def on_context_item_selected(menu_item)
    (instance_eval {menu_item.on_click.call(menu_item.getMenuInfo.position)}) if menu_item.on_click
  end

  #
  # View Generation
  #

  @view_parent = nil

  def self.create_view_factory(view_class)
    class_name = view_class.name.split("::")[-1]
    class_eval "
       def #{(class_name.gsub(/([A-Z])/) {'_' + $1.downcase})[1..-1]}(params={})
          rv = #{class_name}.new self
          @view_parent.addView(rv) if @view_parent
          rv.configure self, params
          if block_given?
            old_view_parent, @view_parent = @view_parent, rv
            yield 
            @view_parent = old_view_parent
          end
          rv
       end
     "
  end

  create_view_factory TextView
  create_view_factory EditText
  create_view_factory Button
  create_view_factory ToggleButton
  create_view_factory ListView
  create_view_factory LinearLayout
#  create_view_factory CheckBox
#  create_view_factory RadioGroup
#  create_view_factory RadioButton
  create_view_factory TableLayout
  create_view_factory TableRow
  create_view_factory ScrollView
#  create_view_factory Spinner
#  create_view_factory AutoCompleteTextView
#  create_view_factory GridView
  create_view_factory TimePicker
  create_view_factory DatePicker
  create_view_factory Chronometer
end
  