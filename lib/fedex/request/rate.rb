require 'business_time'
require 'fedex/request/base'

module Fedex
  module Request
    class Rate < Base
      # Sends post request to Fedex web service and parse the response, a Rate object is created if the response is successful
      def process_request
        api_response = self.class.post(api_url, :body => build_xml)
        puts api_response if @debug
        response = parse_response(api_response)
        if success?(response)
          rate_reply_details = response[:rate_reply][:rate_reply_details] || []
          rate_reply_details = [rate_reply_details] if rate_reply_details.is_a?(Hash)

          rate_reply_details.map do |rate_reply|
            rate_details = [rate_reply[:rated_shipment_details]].flatten.first[:shipment_rate_detail]
            rate_details.merge!(service_type: rate_reply[:service_type], delivery_timestamp: rate_reply[:delivery_timestamp].try(:to_datetime))
            unless rate_details[:delivery_timestamp]
              if @shipping_options[ :ship_timestamp ] && rate_reply[:transit_time]
                transit_time = transit_time_to_number( rate_reply[ :transit_time ] )
                if transit_time
                  rate_details[ :delivery_timestamp ] = transit_time.business_days.after( @shipping_options[ :ship_timestamp ] )
                end
              end
            end
            Fedex::Rate.new(rate_details)
          end
        else
          error_message = if response[:rate_reply]
            [response[:rate_reply][:notifications]].flatten.first[:message]
          else
            "#{api_response["Fault"]["detail"]["fault"]["reason"]}\n--#{api_response["Fault"]["detail"]["fault"]["details"]["ValidationFailureDetail"]["message"].join("\n--")}"
          end rescue $1
          raise RateError, error_message
        end
      end

      private

      TRANSIT_TIME_HASH = {
        "EIGHTEEN_DAYS"  => 18,
        "EIGHT_DAYS"     => 8,
        "ELEVEN_DAYS"    => 11,
        "FIFTEEN_DAYS"   => 15,
        "FIVE_DAYS"      => 5,
        "FOURTEEN_DAYS"  => 14,
        "FOUR_DAYS"      => 4,
        "NINETEEN_DAYS"  => 19,
        "NINE_DAYS"      => 9,
        "ONE_DAY"        => 1,
        "SEVENTEEN_DAYS" => 17,
        "SEVEN_DAYS"     => 7,
        "SIXTEEN_DAYS"   => 16,
        "SIX_DAYS"       => 6,
        "TEN_DAYS"       => 10,
        "THIRTEEN_DAYS"  => 13,
        "THREE_DAYS"     => 3,
        "TWELVE_DAYS"    => 12,
        "TWENTY_DAYS"    => 20,
        "TWO_DAYS"       => 2
      }

      def transit_time_to_number( transit_time )
        # <xs:simpleType name="TransitTimeType">
        #   <xs:restriction base="xs:string">
        #     <xs:enumeration value="EIGHTEEN_DAYS"/>
        #     <xs:enumeration value="EIGHT_DAYS"/>
        #     <xs:enumeration value="ELEVEN_DAYS"/>
        #     <xs:enumeration value="FIFTEEN_DAYS"/>
        #     <xs:enumeration value="FIVE_DAYS"/>
        #     <xs:enumeration value="FOURTEEN_DAYS"/>
        #     <xs:enumeration value="FOUR_DAYS"/>
        #     <xs:enumeration value="NINETEEN_DAYS"/>
        #     <xs:enumeration value="NINE_DAYS"/>
        #     <xs:enumeration value="ONE_DAY"/>
        #     <xs:enumeration value="SEVENTEEN_DAYS"/>
        #     <xs:enumeration value="SEVEN_DAYS"/>
        #     <xs:enumeration value="SIXTEEN_DAYS"/>
        #     <xs:enumeration value="SIX_DAYS"/>
        #     <xs:enumeration value="TEN_DAYS"/>
        #     <xs:enumeration value="THIRTEEN_DAYS"/>
        #     <xs:enumeration value="THREE_DAYS"/>
        #     <xs:enumeration value="TWELVE_DAYS"/>
        #     <xs:enumeration value="TWENTY_DAYS"/>
        #     <xs:enumeration value="TWO_DAYS"/>
        #     <xs:enumeration value="UNKNOWN"/>
        #   </xs:restriction>
        # </xs:simpleType>
        TRANSIT_TIME_HASH[ transit_time ]
      end


      # Add information for shipments
      def add_requested_shipment(xml)
        xml.RequestedShipment{
          if @shipping_options[:ship_timestamp]
            xml.ShipTimestamp @shipping_options[:ship_timestamp].strftime("%FT%T%:z") 
          end
          xml.DropoffType @shipping_options[:drop_off_type] ||= "REGULAR_PICKUP"
          xml.ServiceType service_type if service_type
          xml.PackagingType @shipping_options[:packaging_type] ||= "YOUR_PACKAGING"
          add_shipper(xml)
          add_recipient(xml)
          add_shipping_charges_payment(xml)
          add_customs_clearance(xml) if @customs_clearance
          xml.RateRequestTypes "ACCOUNT"
          add_packages(xml)
        }
      end

      # Build xml Fedex Web Service request
      def build_xml
        ns = "http://fedex.com/ws/rate/v#{service[:version]}"
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.RateRequest(:xmlns => ns){
            add_web_authentication_detail(xml)
            add_client_detail(xml)
            add_version(xml)
            xml.ReturnTransitAndCommit true
            add_requested_shipment(xml)
          }
        end
        builder.doc.root.to_xml
      end

      def service
        { :id => 'crs', :version => 10 }
      end

      # Successful request
      def success?(response)
        response[:rate_reply] &&
          %w{SUCCESS WARNING NOTE}.include?(response[:rate_reply][:highest_severity])
      end

    end
  end
end
