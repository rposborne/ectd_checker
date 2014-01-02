require 'nokogiri'
require 'digest/md5'

Shoes.app title: "eCTD MD5 Repair Tool", width: 900 do


  @window_slot = stack  do

    stack height: 80 do
      background "#888"
      title strong("eCTD MD5 Repair Tool"), margin: 10

      para "Licensed under GPLv2 For other uses contact rposborne at scilucent dot com", margin: 10
      #image File.join(Shoes::DIR, 'static', 'logo.png')
    end

    @progress = progress(width: width, height: 20, margin_top: -2 )
    stack height: 35 do
      @submission_path_slot = para strong("You must select a submission to check"), margin: 10, width: width - 40
      @message_slot = flow
    end
    flow do

      button "Select Submission" do
        @submission_path = ask_open_folder
        @submission_path_slot.text = strong(@submission_path)
        @check_btn.focus
      end

      @check_btn = button("Check Submission") do
        run_submission_checks(false)
      end

      button("Repair Submission") do
        run_submission_checks(true)
      end

      stack width:100 do
        para "Failed", stroke: "#FF0000",  :margin_left => 10, align: "center"
        @failed_slot   = para "", stroke: "#FF0000",  :margin_left => 10, align: "center"
      end
      stack width:100 do
        para "Repaired", stroke: "#005000",  :margin_left => 10, align: "center"
        @repaired_slot   = para "", stroke: "#005000",  :margin_left => 10, align: "center"
      end

      stack width:100 do
        para "Checked", stroke: "#0000FF",  :margin_left => 10, align: "center"
        @checked_slot   = para "", stroke: "#0000FF",  :margin_left => 10, align: "center"
      end

    end

    flow :hidden => true do
      background "#eee"
      para strong("Report:"), size:12, :margin => 10
      @report_slot  = para @report,  :margin => 10, size: 10
    end

  end

  def run_submission_checks(repair)
    @report_ready = false

    Thread.new do
      check_submission_at(@submission_path, repair)
      @report_ready = true
    end

    @report_animate = animate :margin => 10 do
      @report_slot.show
      @report_slot.text = @report
      self.clipboard = @report

      if @report_ready
        if @report_animate
          @report_animate.stop
          @report_animate.remove
        end
        @failed_slot.text   = strong(@failed.to_i)
        @checked_slot.text  = strong(@complete.to_i)
        @repaired_slot.text = strong(@repaired.to_i)
      end
    end

    @progress_animate = animate do
      @progress.fraction = self.percent
      if @progress_animate and @progress.fraction == 1.0
        @progress_animate.stop
        @progress_animate.remove
      end

    end
  end
  def percent
    percent_complete = @complete.to_f / @total_to_check.to_f
    return 0.0 if percent_complete.nan?
    percent_complete
  end

  def log(msg)
    @report += "#{msg} \n"
  end

  def check_submission_at(path, repair)
    begin
      @report = ""
      @total_to_check = 0.0
      @complete = 0
      @failed = 0
      @repaired = 0

      log "Checking: #{path}"
      log "No index.xml Found is this a valid submission?" unless File.exists?(File.join(path, "index.xml"))

      files_to_check = Dir::glob(File.join( path ,"**","*.xml") )

      files_to_check.each do |file|

        f = File.open(file)

        doc = Nokogiri::XML(f)
        leafs =  doc.css('leaf')

        @total_to_check += leafs.size

        leafs.each do |leaf|
          status = "PASSED"
          lead_rel_path = leaf.attributes["href"].to_s
          leaf_full_path = File.join( File.dirname(file.to_s) , lead_rel_path)
          begin
            calculated_checksum = Digest::MD5.hexdigest(File.read(leaf_full_path))
          rescue SystemCallError => e
            log "ERROR #{e.message} at #{lead_rel_path}"
            @complete += 1
            @failed += 1
            next
          end

          leaf_checksum = leaf.attributes["checksum"]

          if calculated_checksum.to_s.chomp != leaf_checksum.to_s.chomp
            @failed += 1
            status = "FAILED"

            if repair
              status = "REPAIRING"
              leaf['checksum'] = calculated_checksum
              @repaired +=1
            end

          end

          log "#{status}  #{lead_rel_path}"

          @complete += 1

        end

        if repair
          log "saving repaired xml at #{file}"
          File.open(file, 'w') {|f| f.write(doc.to_xml) }
        end

        f.close
      end

      index_calculated_checksum = Digest::MD5.file(File.join("#{path}", "index.xml"))
      index_checksum = File.read(File.join("#{path}","index-md5.txt"))

      if index_calculated_checksum != index_checksum
        @failed += 1

        if repair
          @repaired +=1
          log "updating backbone xml md5 #{path}/index-md5.txt"
          File.open(File.join("#{path}","index-md5.txt"), 'w') {|f| f.write(index_calculated_checksum) }
        end
        @complete += 1
      end

      log "#{@failed.to_i} bad checksums"
      log "#{@complete.to_i} checked checksums"
    rescue => e
      log "Fatal Error Detected: #{e}"
      log "Ensure eCTD xml is free of syntax and refrences errors and try again."
      log "Backtrace #{e.backtrace.join("\n")}"
      @complete = 0
      @total_to_check = @complete
      @error = true

    end
  end

end
