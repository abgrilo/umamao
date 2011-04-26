class SuggestionList
  include MongoMapper::EmbeddedDocument

  belongs_to :user

  key :topic_suggestion_ids, Array, :default => []
  has_many :topic_suggestions, :class_name => "Suggestion",
    :in => :topic_suggestion_ids

  key :uninteresting_topic_ids, Array, :default => []
  has_many :uninteresting_topics, :class_name => "Topic",
    :in => :uninteresting_topic_ids

  key :user_suggestion_ids, Array, :default => []
  has_many :user_suggestions, :class_name => "Suggestion",
    :in => :user_suggestion_ids

  key :uninteresting_user_ids, Array, :default => []
  has_many :uninteresting_users, :class_name => "User",
    :in => :uninteresting_user_ids

  def has_been_suggested?(thing)
    if thing.is_a?(Topic)
      self.topic_suggestions.any?{|s| s.entry == thing}
    elsif thing.is_a?(User)
      self.user_suggestions.any?{|s| s.entry == thing}
    else
      raise "Entity can't be suggested to a user: #{thing.class}"
    end
  end

  # Add things to the user's suggestion lists, ignoring the ones that
  # were already suggested, followed, or marked as
  # uninteresting. Works on enumerables as well.
  #
  # options:
  # - limit: maximum number of things to suggest
  # - reason: the reason we are suggesting this thing to the user
  #
  def suggest(thing, options = {})
    limit = options[:limit]
    reason = options[:reason] || "calculated"

    # For some reason, the case statement wasn't working.
    if thing.is_a?(Topic)
      if !self.has_been_suggested?(thing) &&
          !thing.follower_ids.include?(self.user_id) &&
          !self.uninteresting_topic_ids.include?(thing.id)
        suggestion = Suggestion.new(:user => self.user,
                                    :entry_id => thing.id,
                                    :entry_type => thing.class.to_s,
                                    :reason => reason)
        self.topic_suggestions << suggestion
        return 1
      end
    elsif thing.is_a?(User)
      if !self.has_been_suggested?(thing) &&
          self.user.id != thing.id &&
          !self.user.following?(thing) &&
          !self.uninteresting_user_ids.include?(thing.id)
        suggestion = Suggestion.new(:user => self.user,
                                    :entry_id => thing.id,
                                    :entry_type => "User",
                                    :reason => reason)
        self.user_suggestions << suggestion
        return 1
      end
    elsif thing.respond_to?(:each)
      total = 0
      thing.each do |t|
        break if limit.present? && total >= limit
        total += self.suggest(t, :reason => reason)
      end
      return total
    else
      raise "Entity can't be suggested to a user: #{thing.class}"
    end
    return 0
  end

  # Remove a suggestion from the list of suggestions. Destroy the
  # suggestion.
  def remove_suggestion(suggestion_or_entry)
    return if suggestion_or_entry.blank?
    if suggestion_or_entry.is_a?(Suggestion)
      suggestion = suggestion_or_entry
      entry_type = suggestion.entry_type
    else
      entry_id = suggestion_or_entry.id
      entry_type = suggestion_or_entry.class <= Topic ? "Topic" : "User"
      suggestion = Suggestion.first(:entry_id => entry_id,
                                    :entry_type => entry_type,
                                    :user_id => self.user.id)
    end
    return if !suggestion

    if entry_type.constantize < Topic
      self.topic_suggestion_ids.delete(suggestion.id)
    elsif entry_type == "User"
      self.user_suggestion_ids.delete(suggestion.id)
    end
    suggestion.reject!
  end

  # Mark something as uninteresting. Uninteresting users and topics
  # will be ignored in future suggestions.
  def mark_as_uninteresting(thing)
    if thing.is_a?(Topic)
      if !self.uninteresting_topic_ids.include?(thing.id)
        self.uninteresting_topic_ids << thing.id
      end
    elsif thing.is_a?(User)
      if !self.uninteresting_user_ids.include?(thing.id)
        self.uninteresting_user_ids << thing.id
      end
    else
      raise "Entity can't be suggested to a user: #{thing.class}"
    end
  end

  # Refuse and destroy a suggestion. Refused suggestions cannot be
  # re-suggested.
  def refuse_suggestion(suggestion)
    entry = suggestion.entry
    self.mark_as_uninteresting(entry)
    self.remove_suggestion(suggestion)
  end

  # Find suggestions from the user's external accounts.
  def suggest_from_outside
    self.suggest(self.user.find_external_contacts, :reason => "external") +
      self.suggest(self.user.find_external_topics, :reason => "external")
  end

  # Suggest the 20 most followed topics.
  def suggest_popular_topics(limit)
    self.suggest(Topic.query(:order => :followers_count.desc,
                             :limit => limit),
                 :reason => "popular")
  end

  def suggest_users_from_dac(student_class)
    self.suggest(Affiliation.query(
      :student_id.in => student_class.students.map(&:id),
      :user_id.ne => nil).map(&:user),
      :reason => "dac")

    previous_year = AcademicProgramClass.first(
              :academic_program_id => student_class.academic_program_id,
              :year => student_class.year - 1)
    if previous_year
      self.suggest(Affiliation.query(
        :student_id.in => previous_year.students.map(&:id),
        :user_id.ne => nil).map(&:user),
        :reason => "dac")
    end

    next_year = AcademicProgramClass.first(
              :academic_program_id => student_class.academic_program_id,
              :year => student_class.year + 1)
    if next_year
      self.suggest(Affiliation.query(
        :student_id.in => next_year.students.map(&:id),
        :user_id.ne => nil).map(&:user),
        :reason => "dac")
    end
  end


  def suggest_from_dac
    if affiliation = Affiliation.first(:user_id => self.user.id.to_s, :email => /@dac.unicamp.br$/) and student = affiliation.student
      suggestions = []

      # Suggest topics
      if student.academic_program_class
        suggestions << student.academic_program_class.academic_program
      end

      self.suggest(suggestions +
                   student.registered_courses.map(&:course),
                   :reason => "dac")

      # Suggest users
      suggest_users_from_dac(student.academic_program_class) if student.academic_program_class
    end
  end

  # Suggest topics related to the user's affiliations.
  def suggest_university_topics
    if self.user.affiliations.present?
      self.user.affiliations.each do |affiliation|
        self.suggest(affiliation.university.university_topics, "university")
      end
    end
  end

  # Suggest topics related to the user's group invitation.
  def suggest_from_group_invitation
    if group_invitation = GroupInvitation.all(:user_ids => self.user.id).first
      self.suggest(group_invitation.topics, "group_invitation")
    end
  end

  # Populate the user's suggestion list for the signup wizard.
  def find_first_suggestions
    if self.topic_suggestions.blank? &&
        self.user_suggestions.blank?
      self.suggest_from_group_invitation
      self.suggest_university_topics
      self.suggest_from_outside
      self.suggest_from_dac
      if self.topic_suggestion_ids.size < 20
        self.suggest_popular_topics(20 - self.topic_suggestion_ids.size)
      end
    end
  end

  # Recalculate suggestions for the user.
  def refresh_suggestions(type = :all)
    if [:all, :topics].include?(type)
      self.refresh_topic_suggestions
    else
      raise "Don't know how to suggest #{type}"
    end
  end

  def refresh_topic_suggestions
    kept_suggestions = []

    self.topic_suggestions.each do |topic_suggestion|
      if ["external", "university", "dac"].include?(topic_suggestion.reason) &&
          topic_suggestion.entry.present?
        kept_suggestions << topic_suggestion
      else
        topic_suggestion.reject!
      end
    end

    count = Hash.new(0) # Scores for suggestions
    Topic.query(:follower_ids => self.user.id).each do |topic|
      topic.related_topics.each do |related_topic|
        next if related_topic.follower_ids.include?(self.user.id) ||
          self.uninteresting_topic_ids.include?(related_topic.id) ||
          kept_suggestions.any?{|suggestion| suggestion.entry == related_topic}
        count[related_topic.id] += 1
      end
    end

    self.topic_suggestions = kept_suggestions

    count.to_a.sort{|a, b| -(a[1] <=> b[1])}[0 .. 29].each do |topic_count|
      self.topic_suggestions << Suggestion.new(:user => self.user,
                                               :entry_id => topic_count.first,
                                               :entry_type => "Topic",
                                               :reason => "calculated")
    end
  end

end
