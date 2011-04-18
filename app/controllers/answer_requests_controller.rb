# -*- coding: utf-8 -*-
class AnswerRequestsController < ApplicationController
  def new
    @answer_request = AnswerRequest.new(:question_id => params[:question_id])

    respond_to do |format|
      format.js do
        render :json => {
          :success => true,
          :html => render_to_string(:layout => false)}
      end
    end

  end

  def user_autocomplete
    @question = Question.find_by_slug_or_id(params[:question_id])

    respond_to do |format|
      format.js do
        render :partial => "users/autocomplete.js", :type => "text/javascript",
          :locals => {:exclude_user_ids => (@question.requested_users + [current_user]).map(&:id)}
      end
    end
  end

  def create
    @answer_request = AnswerRequest.new
    @answer_request.sender_ids << current_user.id
    @answer_request.safe_update(["question_id", "invited_id", "message"],
                                params[:answer_request])
    @answer_request.save
    respond_to do |format|
      format.js do
        render :json => {
          :success => true,
          :message => "Usuário convidado"
        }
      end
    end
  end
end
